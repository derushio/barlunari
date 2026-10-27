public struct GetLaunchAtLoginUseCase: Sendable {
    private let service: any LaunchAtLoginService

    public init(service: any LaunchAtLoginService) {
        self.service = service
    }

    public func execute() async -> Bool {
        await service.isEnabled()
    }
}

public struct SetLaunchAtLoginUseCase: Sendable {
    private let service: any LaunchAtLoginService

    public init(service: any LaunchAtLoginService) {
        self.service = service
    }

    public func execute(enabled: Bool) async throws {
        try await service.setEnabled(enabled)
    }
}

public struct LoadDisplayModeUseCase: Sendable {
    private let store: any DisplayModeStore

    public init(store: any DisplayModeStore) {
        self.store = store
    }

    /// 保存がなければ既定のモードを返す。
    public func execute() -> CalendarDisplayMode {
        store.load() ?? .default
    }
}

public struct SaveDisplayModeUseCase: Sendable {
    private let store: any DisplayModeStore

    public init(store: any DisplayModeStore) {
        self.store = store
    }

    public func execute(_ mode: CalendarDisplayMode) {
        store.save(mode)
    }
}
