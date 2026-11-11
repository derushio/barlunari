import Foundation
import Testing
@testable import BarlunariInfrastructure

private struct RegistrationError: Error {}

/// `SMAppService` の代わりに、呼び出しを記録し、失敗を決めた回数だけ起こす。
private final class FakeRegistrar: LoginItemRegistrar, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private var registerFailures: Int
    private var unregisterFails: Bool
    private var calls: [String] = []

    init(enabled: Bool, registerFailures: Int = 0, unregisterFails: Bool = false) {
        self.enabled = enabled
        self.registerFailures = registerFailures
        self.unregisterFails = unregisterFails
    }

    var recordedCalls: [String] { lock.withLock { calls } }
    var isEnabled: Bool { lock.withLock { enabled } }
    var isRegistered: Bool { lock.withLock { enabled } }

    func register() throws {
        try lock.withLock {
            calls.append("register")
            if registerFailures > 0 {
                registerFailures -= 1
                throw RegistrationError()
            }
            enabled = true
        }
    }

    func unregister() async throws {
        try lock.withLock {
            calls.append("unregister")
            if unregisterFails { throw RegistrationError() }
            enabled = false
        }
    }
}

private final class FakePathStore: RegisteredBundlePathStore, @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?
    private var pending = false
    init(path: String?) { self.path = path }
    func load() -> String? { lock.withLock { path } }
    func save(_ path: String) { lock.withLock { self.path = path } }
    func isReregistrationPending() -> Bool { lock.withLock { pending } }
    func setReregistrationPending(_ pending: Bool) { lock.withLock { self.pending = pending } }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var sleeps: [Duration] = []
    private var errors: [String] = []
    var recordedSleeps: [Duration] { lock.withLock { sleeps } }
    var recordedErrors: [String] { lock.withLock { errors } }
    func sleep(_ d: Duration) { lock.withLock { sleeps.append(d) } }
    func error(_ m: String) { lock.withLock { errors.append(m) } }
}

private let currentURL = URL(fileURLWithPath: "/Applications/Barlunari.app")
private let currentPath = "/Applications/Barlunari.app"
private let oldPath = "/Users/test/build/Barlunari.app"

private func makeRegistration(
    registrar: FakeRegistrar,
    store: FakePathStore,
    recorder: Recorder
) -> LaunchAtLoginRegistration {
    LaunchAtLoginRegistration(
        registrar: registrar,
        pathStore: store,
        currentBundleURL: currentURL,
        retryDelays: [.milliseconds(1), .milliseconds(2)],
        sleep: { recorder.sleep($0) },
        logError: { recorder.error($0) }
    )
}

@Suite struct LaunchAtLoginRegistrationTests {
    @Test(arguments: [
        (true, Optional(oldPath), true),
        (true, Optional<String>.none, true),
        (true, Optional(currentPath), false),
        (false, Optional(oldPath), false),
        (false, Optional<String>.none, false),
    ])
    func 登録し直しが要るかを判定する(isEnabled: Bool, recorded: String?, expected: Bool) {
        #expect(LaunchAtLoginRegistration.needsReregistration(
            isEnabled: isEnabled, recordedPath: recorded, currentPath: currentPath
        ) == expected)
    }

    @Test func 末尾のスラッシュの違いは同じパスとして扱う() {
        let a = LaunchAtLoginRegistration.normalizedPath(URL(fileURLWithPath: "/Applications/Barlunari.app/"))
        let b = LaunchAtLoginRegistration.normalizedPath(URL(fileURLWithPath: "/Applications/Barlunari.app"))
        #expect(a == b)
    }

    @Test func パスが違えばunregisterしてからregisterし直し今のパスを記録する() async {
        let registrar = FakeRegistrar(enabled: true)
        let store = FakePathStore(path: oldPath)
        let recorder = Recorder()
        await makeRegistration(registrar: registrar, store: store, recorder: recorder).reregisterIfBundleMoved()
        #expect(registrar.recordedCalls == ["unregister", "register"])
        #expect(store.load() == currentPath)
        #expect(recorder.recordedErrors.isEmpty)
    }

    @Test func 記録がなければ違うものとして登録し直す() async {
        let registrar = FakeRegistrar(enabled: true)
        let store = FakePathStore(path: nil)
        await makeRegistration(registrar: registrar, store: store, recorder: Recorder()).reregisterIfBundleMoved()
        #expect(registrar.recordedCalls == ["unregister", "register"])
        #expect(store.load() == currentPath)
    }

    @Test func パスが同じなら何もしない() async {
        let registrar = FakeRegistrar(enabled: true)
        let store = FakePathStore(path: currentPath)
        await makeRegistration(registrar: registrar, store: store, recorder: Recorder()).reregisterIfBundleMoved()
        #expect(registrar.recordedCalls.isEmpty)
    }

    @Test func 無効なら何もしない() async {
        let registrar = FakeRegistrar(enabled: false)
        let store = FakePathStore(path: oldPath)
        await makeRegistration(registrar: registrar, store: store, recorder: Recorder()).reregisterIfBundleMoved()
        #expect(registrar.recordedCalls.isEmpty)
        #expect(store.load() == oldPath)
    }

    @Test func registerが失敗しても待ってから再試行して登録する() async {
        let registrar = FakeRegistrar(enabled: true, registerFailures: 2)
        let store = FakePathStore(path: oldPath)
        let recorder = Recorder()
        await makeRegistration(registrar: registrar, store: store, recorder: recorder).reregisterIfBundleMoved()
        #expect(registrar.recordedCalls == ["unregister", "register", "register", "register"])
        #expect(recorder.recordedSleeps == [.milliseconds(1), .milliseconds(2)])
        #expect(recorder.recordedErrors.count == 2)
        #expect(store.load() == currentPath)
        #expect(registrar.isEnabled)
    }

    @Test func 再試行を使い切ったらエラーを記録しパスを更新しない() async {
        let registrar = FakeRegistrar(enabled: true, registerFailures: 100)
        let store = FakePathStore(path: oldPath)
        let recorder = Recorder()
        await makeRegistration(registrar: registrar, store: store, recorder: recorder).reregisterIfBundleMoved()
        #expect(registrar.recordedCalls == ["unregister", "register", "register", "register"])
        #expect(recorder.recordedErrors.count == 3)
        #expect(store.load() == oldPath)
    }

    @Test func 再試行を使い切ったら次の起動でregisterからやり直す() async {
        // 1 回目の起動では 3 回とも失敗し、2 回目の起動では成功する。
        let registrar = FakeRegistrar(enabled: true, registerFailures: 3)
        let store = FakePathStore(path: oldPath)
        let recorder = Recorder()
        let registration = makeRegistration(registrar: registrar, store: store, recorder: recorder)
        await registration.reregisterIfBundleMoved()
        #expect(!registrar.isEnabled)
        await registration.reregisterIfBundleMoved()
        #expect(registrar.recordedCalls == ["unregister", "register", "register", "register", "register"])
        #expect(registrar.isEnabled)
        #expect(store.load() == currentPath)
    }

    @Test func unregisterが失敗したらregisterせずエラーを記録する() async {
        let registrar = FakeRegistrar(enabled: true, unregisterFails: true)
        let store = FakePathStore(path: oldPath)
        let recorder = Recorder()
        await makeRegistration(registrar: registrar, store: store, recorder: recorder).reregisterIfBundleMoved()
        #expect(registrar.recordedCalls == ["unregister"])
        #expect(recorder.recordedErrors.count == 1)
        #expect(store.load() == oldPath)
    }

    @Test func 設定画面で有効にすると今のパスを記録する() async throws {
        let registrar = FakeRegistrar(enabled: false)
        let store = FakePathStore(path: nil)
        try await makeRegistration(registrar: registrar, store: store, recorder: Recorder()).setEnabled(true)
        #expect(registrar.recordedCalls == ["register"])
        #expect(store.load() == currentPath)
    }

    @Test func 設定画面で有効にしてregisterが失敗したらパスを記録しない() async {
        let registrar = FakeRegistrar(enabled: false, registerFailures: 1)
        let store = FakePathStore(path: nil)
        let registration = makeRegistration(registrar: registrar, store: store, recorder: Recorder())
        await #expect(throws: RegistrationError.self) { try await registration.setEnabled(true) }
        #expect(store.load() == nil)
    }

    @Test func 設定画面で無効にするとunregisterする() async throws {
        let registrar = FakeRegistrar(enabled: true)
        let store = FakePathStore(path: currentPath)
        store.setReregistrationPending(true)
        try await makeRegistration(registrar: registrar, store: store, recorder: Recorder()).setEnabled(false)
        #expect(registrar.recordedCalls == ["unregister"])
        #expect(!store.isReregistrationPending())
    }
}

@Suite struct UserDefaultsRegisteredBundlePathStoreTests {
    @Test func 保存したパスを読み戻せる() {
        let suiteName = "barlunari.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsRegisteredBundlePathStore(defaults: defaults)
        #expect(store.load() == nil)
        store.save(currentPath)
        #expect(UserDefaultsRegisteredBundlePathStore(defaults: defaults).load() == currentPath)
        #expect(!store.isReregistrationPending())
        store.setReregistrationPending(true)
        #expect(UserDefaultsRegisteredBundlePathStore(defaults: defaults).isReregistrationPending())
    }
}
