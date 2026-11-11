import Foundation

/// ログイン項目の登録操作。`SMAppService` を使わずに判定をテストできるよう、操作だけを切り出す。
protocol LoginItemRegistrar: Sendable {
    /// ログイン項目が有効（`SMAppService.Status.enabled`）か。
    var isEnabled: Bool { get }
    /// 無効化の対象になる状態（有効、または承認待ち）か。
    var isRegistered: Bool { get }
    func register() throws
    func unregister() async throws
}

/// 最後に登録したときのバンドルのパスと、登録し直しの途中かの保存先。
protocol RegisteredBundlePathStore: Sendable {
    func load() -> String?
    func save(_ path: String)
    func isReregistrationPending() -> Bool
    func setReregistrationPending(_ pending: Bool)
}

/// `UserDefaults` に登録したバンドルのパスを保存する。
final class UserDefaultsRegisteredBundlePathStore: RegisteredBundlePathStore {
    static let key = "launchAtLoginRegisteredBundlePath"
    static let pendingKey = "launchAtLoginReregistrationPending"

    // UserDefaults はスレッドセーフだが Sendable と宣言されていないため、ここで安全性を保証する。
    private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> String? {
        defaults.string(forKey: Self.key)
    }

    func save(_ path: String) {
        defaults.set(path, forKey: Self.key)
    }

    func isReregistrationPending() -> Bool {
        defaults.bool(forKey: Self.pendingKey)
    }

    func setReregistrationPending(_ pending: Bool) {
        defaults.set(pending, forKey: Self.pendingKey)
    }
}

/// ログイン項目の登録と、登録したバンドルのパスの記録を扱う。
///
/// ログイン項目は登録したときのバンドルの URL を指す。`build/Barlunari.app` で登録したあとに
/// `/Applications` へ入れ替えても、項目は古いパスを指したままになる。そのため、起動時に
/// 登録したパスと今のパスを比べ、違えば unregister してから register し直す。
struct LaunchAtLoginRegistration: Sendable {
    /// unregister の直後の register は "Operation not permitted" で失敗することがある。
    /// 失敗したまま放置するとログイン時の起動が外れたままになるので、待ち時間を伸ばしながら再試行する。
    static let defaultRetryDelays: [Duration] = [.milliseconds(300), .seconds(1), .seconds(3)]

    private let registrar: any LoginItemRegistrar
    private let pathStore: any RegisteredBundlePathStore
    private let currentBundlePath: String
    private let retryDelays: [Duration]
    private let sleep: @Sendable (Duration) async -> Void
    private let logError: @Sendable (String) -> Void

    init(
        registrar: any LoginItemRegistrar,
        pathStore: any RegisteredBundlePathStore,
        currentBundleURL: URL,
        retryDelays: [Duration] = Self.defaultRetryDelays,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        logError: @escaping @Sendable (String) -> Void
    ) {
        self.registrar = registrar
        self.pathStore = pathStore
        self.currentBundlePath = Self.normalizedPath(currentBundleURL)
        self.retryDelays = retryDelays
        self.sleep = sleep
        self.logError = logError
    }

    /// 末尾のスラッシュやシンボリックリンクの違いで別のパスと判定しないよう、正規化したパスにする。
    static func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// 登録し直しが要るか。有効で、記録したパスが今のパスと違う（記録がない場合を含む）ときだけ true。
    static func needsReregistration(isEnabled: Bool, recordedPath: String?, currentPath: String) -> Bool {
        guard isEnabled else { return false }
        return recordedPath != currentPath
    }

    /// 設定画面からの切り替え。有効にしたときは、今のパスを記録する。
    func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            // 登録済みの状態で register すると失敗するため、有効なときは何もしない。
            // 古いパスのまま有効な場合の登録し直しは、起動時の `reregisterIfBundleMoved` が行う。
            if registrar.isEnabled { return }
            try registrar.register()
            pathStore.save(currentBundlePath)
            pathStore.setReregistrationPending(false)
        } else {
            // 利用者が無効にしたら、起動時に登録し直さない。
            pathStore.setReregistrationPending(false)
            guard registrar.isRegistered else { return }
            try await registrar.unregister()
        }
    }

    /// 起動時に呼ぶ。ログイン項目が古いパスを指しているおそれがあれば、登録し直す。
    func reregisterIfBundleMoved() async {
        // 前の起動で解除のあとの register を使い切っていれば、ログイン項目は無効になっている。無効でも register からやり直す。
        let pending = pathStore.isReregistrationPending()
        guard pending || Self.needsReregistration(
            isEnabled: registrar.isEnabled,
            recordedPath: pathStore.load(),
            currentPath: currentBundlePath
        ) else { return }

        if registrar.isRegistered {
            // 解除したあと register を使い切ると、ログイン項目が無効になり、次の起動では有効かどうかで判定できない。
            // 解除する前に、登録し直しの途中であることを記録する。
            pathStore.setReregistrationPending(true)
            do {
                try await registrar.unregister()
            } catch {
                // 解除できなければ、元の登録が残っている。register すると二重になるので何もしない。
                // パスの記録は古いままなので、次の起動でもう一度登録し直す。
                pathStore.setReregistrationPending(pending)
                logError("ログイン項目の登録解除に失敗した: \(error)")
                return
            }
        }

        var attempt = 0
        while true {
            do {
                try registrar.register()
                pathStore.save(currentBundlePath)
                pathStore.setReregistrationPending(false)
                return
            } catch {
                guard attempt < retryDelays.count else {
                    // 登録し直しの途中の記録を残すので、次の起動で register からやり直す。
                    logError("ログイン項目の再登録に失敗した（\(attempt + 1) 回目、あきらめる）: \(error)")
                    return
                }
                logError("ログイン項目の再登録に失敗した（\(attempt + 1) 回目、再試行する）: \(error)")
                await sleep(retryDelays[attempt])
                attempt += 1
            }
        }
    }
}
