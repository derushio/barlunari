import BarlunariDomain

public struct ListCalendarsUseCase: Sendable {
    private let authorizer: any CalendarAccessAuthorizer
    private let calendarRepository: any CalendarRepository
    private let visibilityRepository: any CalendarVisibilityRepository

    public init(
        authorizer: any CalendarAccessAuthorizer,
        calendarRepository: any CalendarRepository,
        visibilityRepository: any CalendarVisibilityRepository
    ) {
        self.authorizer = authorizer
        self.calendarRepository = calendarRepository
        self.visibilityRepository = visibilityRepository
    }

    /// 完全アクセスでなければ、許可の状態に対応する `CalendarAccessError` を投げる。
    /// カレンダーが 1 つもないときは、空の一覧を返す。
    public func execute() async throws -> CalendarList {
        try await authorizer.status().requireFullAccess()
        let accounts = try await calendarRepository.accounts()
        let calendars = try await calendarRepository.calendars()
        let visibility = await visibilityRepository.load()
        return CalendarList(
            accounts: accounts,
            items: calendars.map { CalendarListItem(calendar: $0, isVisible: visibility.isVisible($0.id)) }
        )
    }
}

public struct SetCalendarVisibilityUseCase: Sendable {
    private let visibilityRepository: any CalendarVisibilityRepository

    public init(visibilityRepository: any CalendarVisibilityRepository) {
        self.visibilityRepository = visibilityRepository
    }

    public func execute(calendar: UserCalendar.Identity, isVisible: Bool) async throws {
        try await execute(calendars: [calendar], isVisible: isVisible)
    }

    /// 複数のカレンダーの表示と非表示を、1 回の `update` で原子的に保存する。アカウントのカレンダーをまとめて切り替えるときに使う。
    public func execute(calendars: [UserCalendar.Identity], isVisible: Bool) async throws {
        await visibilityRepository.update { visibility in
            if isVisible {
                visibility.show(contentsOf: calendars)
            } else {
                visibility.hide(contentsOf: calendars)
            }
        }
    }
}
