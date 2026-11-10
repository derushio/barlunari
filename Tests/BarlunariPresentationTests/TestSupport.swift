import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import BarlunariPresentation
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

    /// `waitForRequests(_:)` と `waitForPending(_:)` で待っている呼び出し。件数が届いたときに再開する。
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var pendingWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func gate() { isGated = true }

    var pendingCount: Int { pending.count }

    func events(in interval: DateInterval, calendars: Set<UserCalendar.Identity>) async throws -> [CalendarEvent] {
        requests.append(interval)
        requestedCalendars.append(calendars)
        requestWaiters = Self.resumingReached(requestWaiters, count: requests.count)
        if isGated {
            return await withCheckedContinuation {
                pending.append($0)
                pendingWaiters = Self.resumingReached(pendingWaiters, count: pending.count)
            }
        }
        return try await base.events(in: interval, calendars: calendars)
    }

    /// 取得の呼び出しが `count` 回に達するまで待つ。時間でも回数でも打ち切らないので、並列に動くテストの負荷で遅れても先へ進まない。
    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { requestWaiters.append((count, $0)) }
    }

    /// 返却を止めている取得が `count` 件になるまで待つ。打ち切らないのは `waitForRequests(_:)` と同じ。
    func waitForPending(_ count: Int) async {
        guard pending.count < count else { return }
        await withCheckedContinuation { pendingWaiters.append((count, $0)) }
    }

    private static func resumingReached(
        _ waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)], count: Int
    ) -> [(count: Int, continuation: CheckedContinuation<Void, Never>)] {
        waiters.filter { waiter in
            guard waiter.count <= count else { return true }
            waiter.continuation.resume()
            return false
        }
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
    let responder: FakeEventResponder
    let calendarAppOpener: FakeCalendarAppOpener
    let settingsOpener = FakeSystemSettingsOpener()
    let notifier: DataChangeNotifier
    /// 日付変更などの通知を、システムの通知と混ざらないよう専用の通知センターで流す。
    let notificationCenter = NotificationCenter()
    /// スリープからの復帰の通知を流す専用の通知センター。
    let workspaceNotificationCenter = NotificationCenter()
    let sourceRefresher = FakeCalendarSourceRefresher()
    let calendarRepository: CountingCalendarRepository
    let eventRepository: ScriptedEventRepository
    let dateProvider: MutableDateProvider
    let authorizer: FakeCalendarAccessAuthorizer
    let visibility: InMemoryCalendarVisibilityRepository
    let countdownExclusions: InMemoryCountdownExclusionRepository
    /// ポップオーバーと同じ通知を共有するメニューバーの残り時間。`start()` は呼んでいない。
    let countdown: MenuBarCountdownViewModel
    let launchAtLogin: FakeLaunchAtLoginService
    let displayModeStore: InMemoryDisplayModeStore
    let showDeclinedEventsStore: InMemoryShowDeclinedEventsStore
    let firstWeekdayStore: InMemoryFirstWeekdayStore
    /// ポップオーバーと予定の読み込みに渡す、保存した週の開始曜日で暦を置き換える `DateProvider`。`dateProvider` を包む。
    let overridingDateProvider: FirstWeekdayOverridingDateProvider

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
        displayMode: CalendarDisplayMode? = nil,
        showDeclinedEvents: Bool? = nil,
        firstWeekday: Weekday? = nil,
        responder: FakeEventResponder = FakeEventResponder(),
        calendarAppOpener: FakeCalendarAppOpener = FakeCalendarAppOpener()
    ) {
        self.responder = responder
        self.calendarAppOpener = calendarAppOpener
        displayModeStore = InMemoryDisplayModeStore(mode: displayMode)
        showDeclinedEventsStore = InMemoryShowDeclinedEventsStore(value: showDeclinedEvents)
        firstWeekdayStore = InMemoryFirstWeekdayStore(value: firstWeekday)
        overridingDateProvider = FirstWeekdayOverridingDateProvider(base: dateProvider, store: firstWeekdayStore)
        eventRepository = ScriptedEventRepository(events: events, error: eventError)
        var hidden = CalendarVisibility()
        hiddenCalendars.forEach { hidden.hide($0.id) }
        visibility = InMemoryCalendarVisibilityRepository(visibility: hidden)
        countdownExclusions = InMemoryCountdownExclusionRepository()
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
                showDeclinedEventsStore: showDeclinedEventsStore,
                dateProvider: overridingDateProvider
            ),
            requestCalendarAccess: requestAccess,
            openSystemSettings: openSystemSettings,
            refreshCalendarSources: RefreshCalendarSourcesUseCase(refresher: sourceRefresher),
            respondToEvent: RespondToEventUseCase(responder: responder),
            openEventInCalendarApp: OpenEventInCalendarAppUseCase(opener: calendarAppOpener),
            dateProvider: overridingDateProvider,
            urlOpener: opener,
            changeNotifier: notifier,
            loadDisplayMode: LoadDisplayModeUseCase(store: displayModeStore),
            saveDisplayMode: SaveDisplayModeUseCase(store: displayModeStore),
            listCalendars: ListCalendarsUseCase(
                authorizer: authorizer, calendarRepository: calendarRepository, visibilityRepository: visibility
            ),
            setCalendarVisibility: SetCalendarVisibilityUseCase(visibilityRepository: visibility),
            loadCountdownExclusions: LoadCountdownExclusionsUseCase(repository: countdownExclusions),
            setCountdownExclusion: SetCountdownExclusionUseCase(
                repository: countdownExclusions, dateProvider: overridingDateProvider
            ),
            workspaceNotificationCenter: workspaceNotificationCenter,
            notificationCenter: notificationCenter
        )
        countdown = MenuBarCountdownViewModel(
            loadUpcomingEvents: LoadUpcomingEventsUseCase(
                authorizer: authorizer,
                calendarRepository: calendarRepository,
                eventRepository: eventRepository,
                visibilityRepository: visibility,
                exclusionRepository: countdownExclusions,
                dateProvider: overridingDateProvider
            ),
            dateProvider: overridingDateProvider,
            changeNotifier: notifier,
            workspaceNotificationCenter: workspaceNotificationCenter,
            notificationCenter: notificationCenter
        )
        settings = SettingsViewModel(
            getLaunchAtLogin: GetLaunchAtLoginUseCase(service: launchAtLogin),
            setLaunchAtLogin: SetLaunchAtLoginUseCase(service: launchAtLogin),
            loadShowDeclinedEvents: LoadShowDeclinedEventsUseCase(store: showDeclinedEventsStore),
            saveShowDeclinedEvents: SaveShowDeclinedEventsUseCase(store: showDeclinedEventsStore),
            loadFirstWeekday: LoadFirstWeekdayUseCase(store: firstWeekdayStore),
            saveFirstWeekday: SaveFirstWeekdayUseCase(store: firstWeekdayStore),
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
