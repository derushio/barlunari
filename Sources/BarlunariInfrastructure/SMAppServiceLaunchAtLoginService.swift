import Foundation
import ServiceManagement
import BarlunariApplication

/// `SMAppService.mainApp` を `LoginItemRegistrar` として使う。
struct SMAppServiceRegistrar: LoginItemRegistrar {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    var isRegistered: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() async throws {
        try await SMAppService.mainApp.unregister()
    }
}

/// `SMAppService.mainApp` でログイン時の起動を登録する。登録状態は macOS 側を正とする。
/// 登録したバンドルのパスだけはアプリ側で記録し、起動時に今のパスと違えば登録し直す。
public struct SMAppServiceLaunchAtLoginService: LaunchAtLoginService {
    private let registration: LaunchAtLoginRegistration

    public init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        registration = LaunchAtLoginRegistration(
            registrar: SMAppServiceRegistrar(),
            pathStore: UserDefaultsRegisteredBundlePathStore(defaults: defaults),
            currentBundleURL: Bundle.main.bundleURL,
            logError: { Log.launchAtLogin.error("\($0, privacy: .public)") }
        )
    }

    public func isEnabled() async -> Bool {
        SMAppServiceRegistrar().isEnabled
    }

    public func setEnabled(_ enabled: Bool) async throws {
        try await registration.setEnabled(enabled)
    }

    /// アプリを移した（例: `build/` から `/Applications` へ）あとの起動で、ログイン項目を今のパスに向け直す。
    public func reregisterIfBundleMoved() async {
        await registration.reregisterIfBundleMoved()
    }
}
