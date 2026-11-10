import Foundation
import BarlunariDomain

public struct LoadUpcomingEventsUseCase: Sendable {
    /// 取得する範囲の長さ。残り時間の対象の上限（24 時間）より長く、取得し直す前に対象が尽きにくくする。
    public static let window: TimeInterval = 48 * 60 * 60

    private let authorizer: any CalendarAccessAuthorizer
    private let calendarRepository: any CalendarRepository
    private let eventRepository: any CalendarEventRepository
    private let visibilityRepository: any CalendarVisibilityRepository
    private let settingsRepository: any CountdownTargetSettingsRepository
    private let dateProvider: any DateProvider
    private let agendaBuilder: AgendaBuilder

    public init(
        authorizer: any CalendarAccessAuthorizer,
        calendarRepository: any CalendarRepository,
        eventRepository: any CalendarEventRepository,
        visibilityRepository: any CalendarVisibilityRepository,
        settingsRepository: any CountdownTargetSettingsRepository,
        dateProvider: any DateProvider,
        agendaBuilder: AgendaBuilder = AgendaBuilder()
    ) {
        self.authorizer = authorizer
        self.calendarRepository = calendarRepository
        self.eventRepository = eventRepository
        self.visibilityRepository = visibilityRepository
        self.settingsRepository = settingsRepository
        self.dateProvider = dateProvider
        self.agendaBuilder = agendaBuilder
    }

    /// 現在から `window` の範囲に重なる、表示中のカレンダーの予定を返す。辞退した予定も含む（詳細のチェックボックスの設定は辞退した予定にもある。数えるかどうかは `NextEventCountdown` が決める）。
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
                includesDeclined: true
            ),
            settings: await settingsRepository.load(),
            rangeEnd: interval.end,
            calendar: dateProvider.calendar
        )
    }
}

public struct LoadCountdownTargetSettingsUseCase: Sendable {
    private let repository: any CountdownTargetSettingsRepository

    public init(repository: any CountdownTargetSettingsRepository) {
        self.repository = repository
    }

    public func execute() async -> CountdownTargetSettings {
        await repository.load()
    }
}

public struct SetCountdownTargetUseCase: Sendable {
    private let repository: any CountdownTargetSettingsRepository

    public init(repository: any CountdownTargetSettingsRepository) {
        self.repository = repository
    }

    /// 予定を残り時間の対象にするか、対象外にするかを保存する。
    ///
    /// 設定は回ごとの予定の ID に結び付けて持ち、時間が経っても消さない。
    ///
    /// - Throws: 保存に失敗したとき。
    public func execute(event: CalendarEvent.Identity, isTarget: Bool) async throws {
        try await repository.update { settings in
            settings.set(event, isTarget: isTarget)
        }
    }
}
