import Foundation
import BarlunariDomain

public struct LoadUpcomingEventsUseCase: Sendable {
    /// 取得する範囲の長さ。残り時間の対象の上限（24 時間）より長く、取得し直す前に対象が尽きにくくする。
    public static let window: TimeInterval = 48 * 60 * 60

    private let authorizer: any CalendarAccessAuthorizer
    private let calendarRepository: any CalendarRepository
    private let eventRepository: any CalendarEventRepository
    private let visibilityRepository: any CalendarVisibilityRepository
    private let exclusionRepository: any CountdownExclusionRepository
    private let dateProvider: any DateProvider
    private let agendaBuilder: AgendaBuilder

    public init(
        authorizer: any CalendarAccessAuthorizer,
        calendarRepository: any CalendarRepository,
        eventRepository: any CalendarEventRepository,
        visibilityRepository: any CalendarVisibilityRepository,
        exclusionRepository: any CountdownExclusionRepository,
        dateProvider: any DateProvider,
        agendaBuilder: AgendaBuilder = AgendaBuilder()
    ) {
        self.authorizer = authorizer
        self.calendarRepository = calendarRepository
        self.eventRepository = eventRepository
        self.visibilityRepository = visibilityRepository
        self.exclusionRepository = exclusionRepository
        self.dateProvider = dateProvider
        self.agendaBuilder = agendaBuilder
    }

    /// 現在から `window` の範囲に重なる、表示中のカレンダーの予定を返す。辞退した予定は、設定にかかわらず除く。
    ///
    /// - Throws: 完全アクセスでなければ `.notDetermined` か `.denied`、カレンダーが 1 つもなければ `.noCalendars`。
    ///   予定の取得の失敗は、そのまま投げる。
    public func execute() async throws -> UpcomingEvents {
        try await authorizer.status().requireFullAccess()
        let now = dateProvider.now
        let accounts = try await calendarRepository.accounts()
        let calendars = try await calendarRepository.calendars()
        guard !calendars.isEmpty else { throw CalendarAccessError.noCalendars }

        let visibility = await visibilityRepository.load()
        let visibleIdentities = Set(calendars.map(\.id).filter(visibility.isVisible))
        let interval = DateInterval(start: now, duration: Self.window)
        let events = visibleIdentities.isEmpty
            ? []
            : try await eventRepository.events(in: interval, calendars: visibleIdentities)

        return UpcomingEvents(
            events: agendaBuilder.candidateEvents(
                from: events,
                visibleCalendars: visibleIdentities,
                accountOrder: accounts.map(\.id),
                includesDeclined: false
            ),
            exclusions: await exclusionRepository.load(),
            rangeEnd: interval.end
        )
    }
}

public struct LoadCountdownExclusionsUseCase: Sendable {
    private let repository: any CountdownExclusionRepository

    public init(repository: any CountdownExclusionRepository) {
        self.repository = repository
    }

    public func execute() async -> CountdownExclusions {
        await repository.load()
    }
}

public struct SetCountdownExclusionUseCase: Sendable {
    private let repository: any CountdownExclusionRepository
    private let dateProvider: any DateProvider

    public init(repository: any CountdownExclusionRepository, dateProvider: any DateProvider) {
        self.repository = repository
        self.dateProvider = dateProvider
    }

    /// 予定を残り時間の対象から外す、または戻す。`start` は予定の開始日時である。
    ///
    /// 保存するとき、開始日時が現在時刻より前の項目を消して、保存が増え続けないようにする。
    ///
    /// - Throws: 保存に失敗したとき。
    public func execute(event: CalendarEvent.Identity, start: Date, isExcluded: Bool) async throws {
        let now = dateProvider.now
        try await repository.update { exclusions in
            if isExcluded {
                exclusions.exclude(event, start: start)
            } else {
                exclusions.include(event)
            }
            exclusions.removeEntries(startingBefore: now)
        }
    }
}
