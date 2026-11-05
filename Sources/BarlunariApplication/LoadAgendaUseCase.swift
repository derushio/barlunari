import Foundation
import BarlunariDomain

public struct LoadAgendaUseCase: Sendable {
    private let authorizer: any CalendarAccessAuthorizer
    private let calendarRepository: any CalendarRepository
    private let eventRepository: any CalendarEventRepository
    private let visibilityRepository: any CalendarVisibilityRepository
    private let showDeclinedEventsStore: any ShowDeclinedEventsStore
    private let dateProvider: any DateProvider
    private let agendaBuilder: AgendaBuilder

    public init(
        authorizer: any CalendarAccessAuthorizer,
        calendarRepository: any CalendarRepository,
        eventRepository: any CalendarEventRepository,
        visibilityRepository: any CalendarVisibilityRepository,
        showDeclinedEventsStore: any ShowDeclinedEventsStore,
        dateProvider: any DateProvider,
        agendaBuilder: AgendaBuilder = AgendaBuilder()
    ) {
        self.authorizer = authorizer
        self.calendarRepository = calendarRepository
        self.eventRepository = eventRepository
        self.visibilityRepository = visibilityRepository
        self.showDeclinedEventsStore = showDeclinedEventsStore
        self.dateProvider = dateProvider
        self.agendaBuilder = agendaBuilder
    }

    /// 辞退した予定を含めるかは、実行のたびに `showDeclinedEventsStore` から読む。保存がなければ含める。
    ///
    /// - Throws: 完全アクセスでなければ `.notDetermined` か `.denied`、カレンダーが 1 つもなければ `.noCalendars`。
    ///   予定の取得の失敗は、カレンダー単位に分けずに、そのまま投げる。
    public func execute(range: DayRange) async throws -> AgendaSnapshot {
        try await authorizer.status().requireFullAccess()
        let calendar = dateProvider.calendar
        let accounts = try await calendarRepository.accounts()
        let calendars = try await calendarRepository.calendars()
        guard !calendars.isEmpty else { throw CalendarAccessError.noCalendars }

        let visibility = await visibilityRepository.load()
        let visibleCalendars = calendars.filter { visibility.isVisible($0.id) }
        let visibleIdentities = Set(visibleCalendars.map(\.id))
        let events = visibleIdentities.isEmpty
            ? []
            : try await eventRepository.events(in: range.dateInterval(calendar: calendar), calendars: visibleIdentities)

        let days = agendaBuilder.build(
            events: events,
            visibleCalendars: visibleIdentities,
            accountOrder: accounts.map(\.id),
            includesDeclined: showDeclinedEventsStore.load() ?? ShowDeclinedEventsDefault.value,
            range: range,
            calendar: calendar
        )
        return AgendaSnapshot(
            days: days,
            colorsByDay: agendaBuilder.colorsByDay(of: days, calendars: visibleCalendars),
            calendars: visibleCalendars,
            accounts: accounts
        )
    }
}
