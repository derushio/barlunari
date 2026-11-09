import BarlunariDomain

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

public struct LoadShowDeclinedEventsUseCase: Sendable {
    private let store: any ShowDeclinedEventsStore

    public init(store: any ShowDeclinedEventsStore) {
        self.store = store
    }

    /// 保存がなければ既定の値（表示する）を返す。
    public func execute() -> Bool {
        store.load() ?? ShowDeclinedEventsDefault.value
    }
}

public struct SaveShowDeclinedEventsUseCase: Sendable {
    private let store: any ShowDeclinedEventsStore

    public init(store: any ShowDeclinedEventsStore) {
        self.store = store
    }

    public func execute(_ show: Bool) {
        store.save(show)
    }
}

public struct LoadFirstWeekdayUseCase: Sendable {
    private let store: any FirstWeekdayStore

    public init(store: any FirstWeekdayStore) {
        self.store = store
    }

    /// 保存した曜日。保存がなければ `nil`（システムの設定に従う）。
    public func execute() -> Weekday? {
        store.load()
    }
}

public struct SaveFirstWeekdayUseCase: Sendable {
    private let store: any FirstWeekdayStore

    public init(store: any FirstWeekdayStore) {
        self.store = store
    }

    /// `nil` なら保存を消し、システムの設定に従う。
    public func execute(_ weekday: Weekday?) {
        store.save(weekday)
    }
}
