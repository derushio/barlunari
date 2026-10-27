import ServiceManagement
import MenuDateApplication

/// `SMAppService.mainApp` でログイン時の起動を登録する。登録状態は macOS 側を正とする。
public struct SMAppServiceLaunchAtLoginService: LaunchAtLoginService {
    public init() {}

    public func isEnabled() async -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) async throws {
        let service = SMAppService.mainApp
        if enabled {
            // 登録済みの状態で register すると失敗するため、有効なときは何もしない。
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled || service.status == .requiresApproval else { return }
            try await service.unregister()
        }
    }
}
