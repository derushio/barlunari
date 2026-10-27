import Foundation
import MenuDateApplication
import MenuDateDomain
import MenuDatePreviewSupport
import MenuDatePresentation
import Synchronization

/// 時刻を差し替えられる `DateProvider`。
final class MutableDateProvider: DateProvider {
    private let current: Mutex<Date>
    private let currentCalendar: Mutex<Calendar>

    init(now: Date = SampleData.now, calendar: Calendar = SampleData.calendar) {
        self.current = Mutex(now)
        self.currentCalendar = Mutex(calendar)
    }

    var now: Date { current.withLock { $0 } }
    var calendar: Calendar { currentCalendar.withLock { $0 } }

    func set(_ date: Date) {
        current.withLock { $0 = date }
    }

    func set(calendar: Calendar) {
        currentCalendar.withLock { $0 = calendar }
    }
}

/// 呼び出しを記録し、必要なら結果の返却を止められる予定のリポジトリ。
///
/// `gate()` の後の呼び出しは `resume(at:events:)` が呼ばれるまで返らない。
/// 古い読み込みの結果が新しい結果を上書きしないことを、時間待ちなしで確かめるために使う。
actor ScriptedEventRepository: CalendarEventRepository {
    private let base: InMemoryCalendarEventRepository
    private var isGated = false
    private var pending: [CheckedContinuation<[CalendarEvent], Never>] = []
    private(set) var requests: [DateInterval] = []
    private(set) var requestedCalendars: [Set<UserCalendar.Identity>] = []

    init(events: [CalendarEvent] = SampleData.events, error: (any Error)? = nil) {
        base = InMemoryCalendarEventRepository(events: events, error: error)
    }

    func gate() { isGated = true }

    var pendingCount: Int { pending.count }

    func events(in interval: DateInterval, calendars: Set<UserCalendar.Identity>) async throws -> [CalendarEvent] {
        requests.append(interval)
        requestedCalendars.append(calendars)
        if isGated {
            return await withCheckedContinuation { pending.append($0) }
        }
        return try await base.events(in: interval, calendars: calendars)
    }

    func resume(at index: Int, events: [CalendarEvent]) {
        pending[index].resume(returning: events)
    }
}

/// `calendars()` の呼び出し回数を数えるカレンダーのリポジトリ。
actor CountingCalendarRepository: CalendarRepository {
    private let base: InMemoryCalendarRepository
    private(set) var callCount = 0

    init(accounts: [UserAccount] = SampleData.accounts, calendars: [UserCalendar] = SampleData.calendars) {
        base = InMemoryCalendarRepository(accounts: accounts, calendars: calendars)
    }

    func accounts() async throws -> [UserAccount] {
        try await base.accounts()
    }

    func calendars() async throws -> [UserCalendar] {
        callCount += 1
        return try await base.calendars()
    }
}

/// ViewModel を、PreviewSupport のフェイクと本物のユースケースで組み立てる。
@MainActor
struct Harness {
    let popover: CalendarPopoverViewModel
    let settings: SettingsViewModel
    let opener = FakeURLOpener()
    let settingsOpener = FakeSystemSettingsOpener()
    let notifier: DataChangeNotifier
    /// 日付変更などの通知を、システムの通知と混ざらないよう専用の通知センターで流す。
    let notificationCenter = NotificationCenter()
    let calendarRepository: CountingCalendarRepository
    let eventRepository: ScriptedEventRepository
    let dateProvider: MutableDateProvider
    let authorizer: FakeCalendarAccessAuthorizer
    let visibility: InMemoryCalendarVisibilityRepository
    let launchAtLogin: FakeLaunchAtLoginService
    let displayModeStore: InMemoryDisplayModeStore

    init(
        status: CalendarAuthorizationStatus = .fullAccess,
        statusAfterRequest: CalendarAuthorizationStatus = .fullAccess,
        requestError: (any Error)? = nil,
        accounts: [UserAccount] = SampleData.accounts,
        calendars: [UserCalendar] = SampleData.calendars,
        events: [CalendarEvent] = SampleData.events,
        eventError: (any Error)? = nil,
        launchAtLoginError: (any Error)? = nil,
        hiddenCalendars: [UserCalendar] = [],
        dateProvider: MutableDateProvider = MutableDateProvider(),
        displayMode: CalendarDisplayMode? = nil
    ) {
        displayModeStore = InMemoryDisplayModeStore(mode: displayMode)
        eventRepository = ScriptedEventRepository(events: events, error: eventError)
        var hidden = CalendarVisibility()
        hiddenCalendars.forEach { hidden.hide($0.id) }
        visibility = InMemoryCalendarVisibilityRepository(visibility: hidden)
        calendarRepository = CountingCalendarRepository(accounts: accounts, calendars: calendars)
        authorizer = FakeCalendarAccessAuthorizer(
            status: status, statusAfterRequest: statusAfterRequest, requestError: requestError
        )
        launchAtLogin = FakeLaunchAtLoginService(setEnabledError: launchAtLoginError)
        notifier = DataChangeNotifier()
        self.dateProvider = dateProvider
        let requestAccess = RequestCalendarAccessUseCase(authorizer: authorizer)
        let openSystemSettings = OpenSystemSettingsUseCase(opener: settingsOpener)

        popover = CalendarPopoverViewModel(
            loadAgenda: LoadAgendaUseCase(
                authorizer: authorizer,
                calendarRepository: calendarRepository,
                eventRepository: eventRepository,
                visibilityRepository: visibility,
                dateProvider: dateProvider
            ),
            requestCalendarAccess: requestAccess,
            openSystemSettings: openSystemSettings,
            dateProvider: dateProvider,
            urlOpener: opener,
            changeNotifier: notifier,
            loadDisplayMode: LoadDisplayModeUseCase(store: displayModeStore),
            saveDisplayMode: SaveDisplayModeUseCase(store: displayModeStore),
            listCalendars: ListCalendarsUseCase(
                authorizer: authorizer, calendarRepository: calendarRepository, visibilityRepository: visibility
            ),
            setCalendarVisibility: SetCalendarVisibilityUseCase(visibilityRepository: visibility),
            notificationCenter: notificationCenter
        )
        settings = SettingsViewModel(
            getLaunchAtLogin: GetLaunchAtLoginUseCase(service: launchAtLogin),
            setLaunchAtLogin: SetLaunchAtLoginUseCase(service: launchAtLogin),
            listCalendars: ListCalendarsUseCase(
                authorizer: authorizer, calendarRepository: calendarRepository, visibilityRepository: visibility
            ),
            setCalendarVisibility: SetCalendarVisibilityUseCase(visibilityRepository: visibility),
            requestCalendarAccess: requestAccess,
            openSystemSettings: openSystemSettings,
            changeNotifier: notifier,
            notificationCenter: notificationCenter
        )
    }

    /// 最初の読み込みを終えた状態のポップオーバーを返す。
    func loadedPopover() async -> CalendarPopoverViewModel {
        popover.reload()
        await popover.waitForLoad()
        return popover
    }
}

/// 条件が成り立つまで実行を譲る。時間は待たない。通知の配送など、メインキューを経由する処理の完了に使う。
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<1000 where !condition() { await Task.yield() }
}

func yieldRepeatedly(_ count: Int = 200) async {
    for _ in 0..<count { await Task.yield() }
}

extension CalendarPopoverViewModel {
    /// 日のセクション。一覧の範囲の外の日では失敗させる。
    func section(of day: CalendarDay) -> AgendaSectionState {
        guard let index = agendaIndex(of: day), let section = agendaSection(at: index) else {
            preconditionFailure("一覧の範囲の外の日: \(day)")
        }
        return section
    }

    /// 選択日のセクション。
    var selectedSection: AgendaSectionState { section(of: selectedDay) }

    /// `day` から `count` 日分のセクション。
    func sections(from day: CalendarDay, count: Int) -> [AgendaSectionState] {
        let start = agendaIndex(of: day) ?? 0
        return (start..<min(start + count, agendaDayCount)).compactMap(agendaSection(at:))
    }

    /// 一覧の全日のセクション。
    var allSections: [AgendaSectionState] { sections(from: agendaRange.start, count: agendaDayCount) }
}

extension CalendarPopoverViewModel {
    /// 表示月の最初の週から 6 週分の日。マス目が止まったときに見せる内容。
    var weeks: [[DayCellState]] {
        (0..<WeekTimeline.visibleWeekCount).map { weekCells(at: displayedMonthFirstWeek + $0) }
    }
}
