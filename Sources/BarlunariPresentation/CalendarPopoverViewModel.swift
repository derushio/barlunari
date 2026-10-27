import AppKit
import Foundation
import BarlunariApplication
import BarlunariDomain
import Observation

/// メニューバーのポップオーバーの状態と操作。
///
/// 予定一覧の日の範囲は、月のマス目が表示できる月の日（`WeekTimeline.selectableDayRange`）に固定する。選べる日も同じ範囲である。
/// 範囲は広げず、削らない。作り直すのは、週の開始曜日が変わったときと、今日を含む週が変わったときだけである。
/// 予定は、この全範囲を一度の読み込みで取得する。
/// 選択日は、利用者のスクロールでは一覧の一番上の日に追従し、それ以外の操作では一覧のスクロールを要求する。
@MainActor
@Observable
public final class CalendarPopoverViewModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        /// 許可の状態やカレンダーの有無により、予定の代わりに案内を出す。
        case guide(CalendarAccessGuide)
        /// 利用者に見せる日本語の文を持つ。
        case failed(String)
    }

    /// 前回の読み込みからこの秒数を過ぎていたら、ポップオーバーを開いたときに読み込み直す。
    static let staleInterval: TimeInterval = 60

    /// パネルを開いていなくても、この間隔でサーバーとの同期を OS に求める。
    static let syncInterval: Duration = .seconds(180)
    /// `syncInterval` の 10% 以上。OS が起こす時刻をほかのタイマーとまとめられるようにする。
    static let syncTolerance: Duration = .seconds(30)

    public private(set) var displayedMonth: CalendarMonth {
        didSet { untrackedDisplayedMonth = displayedMonth }
    }
    /// `displayedMonth` の写し。観測に登録せずに読むために持つ。
    @ObservationIgnored private var untrackedDisplayedMonth: CalendarMonth
    public private(set) var selectedDay: CalendarDay
    public private(set) var phase: Phase = .idle
    public private(set) var snapshot: AgendaSnapshot = .empty
    public private(set) var lastUpdated: Date?
    /// 詳細を表示している予定。`nil` なら予定一覧を表示する。
    public private(set) var detailEventID: CalendarEvent.Identity?
    /// ポップオーバーの表示モード。起動時に保存した値を読み、`setDisplayMode(_:)` で変える。
    public private(set) var displayMode: CalendarDisplayMode
    /// View に一覧のスクロールを求める要求。ViewModel が選択日を変えたときだけ更新する。利用者のスクロールでは更新しない。
    public private(set) var agendaScrollRequest: AgendaScrollRequest?
    /// View に月のマス目のスクロールを求める要求。ViewModel が表示月を変えたときだけ更新する。利用者のマス目のスクロールでは更新しない。
    public private(set) var gridScrollRequest: GridScrollRequest?
    /// マス目の週の並び。今日を含む週の前後に固定の数の週を並べ、後から足さない。週の開始曜日が変わったときと、今日を含む週が変わったときだけ作り直す。
    @ObservationIgnored private var timeline: WeekTimeline

    private var loadedRange: DayRange?
    /// 読み込み中の範囲。進行中の読み込みが、いま必要な範囲を含んでいれば、読み込み直さないために使う。
    private var loadingRange: DayRange?
    /// 日ごとの予定。読み込みのたびに一度だけ作り、セクションごとには作り直さない。
    private var eventsByDay: [CalendarDay: [CalendarEvent]] = [:]
    /// カレンダーの色。読み込みのたびに一度だけ作り、週の行ごとには作り直さない。
    private var calendarColors: [UserCalendar.Identity: CalendarColor] = [:]
    /// 前回の表示までに確認した今日。これと今日が違えば、日付が変わったとみなして選択を今日に戻す。
    private var lastSeenToday: CalendarDay
    /// 日付の変化などで画面の表示を作り直させるための通し番号。値自体に意味はない。
    private var clockRevision = 0
    /// 予定の読み込みのたびに進める通し番号。月表示の予定の配置の記憶を捨てる印の一部で、予定の層が読み込みを検知するためにも読む（観測の対象）。
    private var dataRevision = 0
    /// 月表示の週ごとの予定の配置の記憶。観測の対象にしない。
    @ObservationIgnored private var monthLayoutCache = MonthWeekLayoutCache()
    /// 月表示の週ごとの描画結果（画像）の記憶。観測の対象にしない。予定の読み込みと日付の変化で捨てる。
    @ObservationIgnored let monthImageStore = MonthWeekImageStore()
    /// 解放時に通知の購読を解除する。
    @ObservationIgnored private var observations: [NotificationObservation] = []
    /// パネルを開いていなくても同期を求め続ける。解放時に止まる。
    @ObservationIgnored private var syncTimer: RepeatingTask?

    // MARK: 表示するカレンダーの一覧

    /// 表示するカレンダーの一覧の状態。
    public enum CalendarFilterPhase: Equatable, Sendable {
        case loading
        case loaded
        /// 許可の状態やカレンダーの有無により、一覧を出せない。利用者に見せる日本語の文を持つ。
        case unavailable(String)
    }

    /// 表示するカレンダーの一覧を開いているか。月表示は右側のパネル、コンパクト表示は予定一覧の位置に出す。
    public private(set) var isCalendarFilterOpen = false
    public private(set) var calendarFilterPhase: CalendarFilterPhase = .loading
    /// 一覧に出すアカウントごとのカレンダーと表示状態。
    public private(set) var calendarFilterSections: [CalendarAccountSection] = []
    /// 切り替えに失敗したときの、利用者に見せる日本語の文。
    public private(set) var calendarFilterError: String?
    /// 一覧の内容を変えるたび（読み込みの開始、切り替え）に進める通し番号。これより前に始まった読み込みの結果は捨てる。
    @ObservationIgnored private var calendarFilterGeneration = 0
    @ObservationIgnored private var calendarFilterTask: Task<Void, Never>?

    /// 読み込みを始めてから終えるまで `true`。開いた直後の二重の呼び出しで、進行中の読み込みを取り消さないために使う。
    private var isLoadInFlight = false
    /// 読み込み中に変更通知が届いたら立てる。読み込みが終わったとき、立っていれば 1 回だけ読み直す。
    private var needsReloadAfterLoad = false
    /// ポップオーバー自身のウインドウ。設定ウインドウなど他のウインドウが key になっても反応しないために使う。
    @ObservationIgnored private var popoverWindowID: ObjectIdentifier?
    private var loadTask: Task<Void, Never>?
    /// 古い読み込みの結果を捨てるための通し番号。キャンセルを無視する処理が混ざっても上書きされない。
    private var loadGeneration = 0

    /// 許可を求めている間は `true`。許可のダイアログは 1 つしか出せないため、続けて押されても求め直さない。
    public private(set) var isRequestingAccess = false

    private let loadAgenda: LoadAgendaUseCase
    private let requestCalendarAccess: RequestCalendarAccessUseCase
    private let openSystemSettings: OpenSystemSettingsUseCase
    private let refreshCalendarSources: RefreshCalendarSourcesUseCase
    private let dateProvider: any DateProvider
    private let urlOpener: any URLOpener
    private let changeNotifier: DataChangeNotifier
    private let currentFormatter: CurrentCalendarFormatter
    private let saveDisplayMode: SaveDisplayModeUseCase
    private let listCalendars: ListCalendarsUseCase
    private let setCalendarVisibility: SetCalendarVisibilityUseCase

    public init(
        loadAgenda: LoadAgendaUseCase,
        requestCalendarAccess: RequestCalendarAccessUseCase,
        openSystemSettings: OpenSystemSettingsUseCase,
        refreshCalendarSources: RefreshCalendarSourcesUseCase,
        dateProvider: any DateProvider,
        urlOpener: any URLOpener,
        changeNotifier: DataChangeNotifier,
        loadDisplayMode: LoadDisplayModeUseCase,
        saveDisplayMode: SaveDisplayModeUseCase,
        listCalendars: ListCalendarsUseCase,
        setCalendarVisibility: SetCalendarVisibilityUseCase,
        workspaceNotificationCenter: NotificationCenter,
        notificationCenter: NotificationCenter = .default
    ) {
        self.loadAgenda = loadAgenda
        self.requestCalendarAccess = requestCalendarAccess
        self.openSystemSettings = openSystemSettings
        self.refreshCalendarSources = refreshCalendarSources
        self.dateProvider = dateProvider
        self.urlOpener = urlOpener
        self.changeNotifier = changeNotifier
        self.currentFormatter = CurrentCalendarFormatter(dateProvider: dateProvider)
        self.saveDisplayMode = saveDisplayMode
        self.listCalendars = listCalendars
        self.setCalendarVisibility = setCalendarVisibility
        self.displayMode = loadDisplayMode.execute()

        let today = CalendarDay(date: dateProvider.now, calendar: dateProvider.calendar)
        self.selectedDay = today
        self.displayedMonth = today.calendarMonth
        self.untrackedDisplayedMonth = today.calendarMonth
        self.lastSeenToday = today
        self.timeline = Self.makeTimeline(today: today, firstWeekday: dateProvider.calendar.firstWeekday)

        // 日付の変更に加え、タイムゾーンと地域設定（週の開始曜日）の変更でも今日と表示を求め直す。
        let names: [Notification.Name] = [
            .NSCalendarDayChanged, .NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification,
        ]
        var observations = names.map { name in
            NotificationObservation(center: notificationCenter, name: name) { [weak self] _ in
                // queue に .main を指定しているため、メインスレッドで呼ばれる。
                MainActor.assumeIsolated { self?.systemCalendarDidChange() }
            }
        }
        // カレンダーのデータが変わったら、今日や選択日はそのままに、予定だけを読み直す。
        // 同期は求めない。同期、変更通知、同期の連鎖を起こさないためである。
        observations.append(NotificationObservation(center: notificationCenter, name: .calendarStoreDidChange) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadForStoreChange() }
        })
        // スリープから復帰したら、止まっていた同期を求め、読み直す。
        observations.append(NotificationObservation(center: workspaceNotificationCenter, name: NSWorkspace.didWakeNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        self.observations = observations
        syncTimer = RepeatingTask(interval: Self.syncInterval, tolerance: Self.syncTolerance) { [weak self] in
            self?.requestSourceSync()
        }
    }

    /// 呼ぶたびに現在の暦で書式を選ぶ。マス目の日付と見出しの週の開始曜日を食い違わせないため。
    private var formatter: CalendarFormatter { currentFormatter.formatter }

    // MARK: - 表示内容

    public var today: CalendarDay {
        _ = clockRevision
        return CalendarDay(date: dateProvider.now, calendar: dateProvider.calendar)
    }

    public var monthTitle: String { formatter.monthTitle(displayedMonth) }

    public var weekdaySymbols: [String] { formatter.weekdaySymbolsFromFirstWeekday() }

    /// マス目に並べる週の数。
    public var weekCount: Int { weekTimeline.weekCount }

    /// 表示月の最初の週の番号。マス目はこの週を一番上にして始める。
    public var displayedMonthFirstWeek: Int {
        let timeline = weekTimeline
        return timeline.firstWeekIndex(of: displayedMonth) ?? timeline.todayWeekIndex
    }

    /// マス目の初期位置にする週の番号。`displayedMonthFirstWeek` と同じだが、観測に登録しない。
    ///
    /// マス目の View の `init` は親の body の中で呼ばれる。そこで `displayedMonthFirstWeek` を読むと、表示月が変わるたびに
    /// 親の body とマス目の View の body が評価し直される。初期位置は作るときの 1 回だけ必要なので、観測に登録せずに読む。
    public var initialGridWeek: Int {
        let timeline = weekTimeline
        return timeline.firstWeekIndex(of: untrackedDisplayedMonth) ?? timeline.todayWeekIndex
    }

    /// 番号の週の 7 日の表示内容。行の View が自分の週だけを読むための入口で、全週の配列は作らない。
    public func weekCells(at index: Int) -> [DayCellState] {
        let today = self.today
        let displayedMonth = self.displayedMonth
        let selectedDay = self.selectedDay
        let formatter = self.formatter
        let timeline = weekTimeline
        return timeline.days(inWeek: index).map { day in
            DayCellState(
                day: day,
                isInMonth: displayedMonth.contains(day),
                isToday: day == today,
                isSelected: day == selectedDay,
                isSelectable: timeline.isSelectable(day),
                weekdayKind: weekdayKind(of: day, formatter: formatter),
                dotColors: Array((snapshot.colorsByDay[day] ?? []).prefix(3)),
                accessibilityLabel: currentFormatter.dayHeader(day)
            )
        }
    }

    /// 月表示で、番号の週の 7 日の表示内容と予定の配置。行の View が自分の週だけを読むための入口で、全週の配列は作らない。
    ///
    /// 月表示の行の View は、層ごとに `monthWeekDays(at:)`、`monthWeekLayout(at:)`、`selectedColumn(inWeek:)` を読む。
    public func monthWeek(at index: Int) -> MonthWeekState {
        MonthWeekState(cells: weekCells(at: index), layout: monthWeekLayout(at: index))
    }

    /// 月表示のマスの層が読む、番号の週の 7 日の表示内容。表示月と選択日を読まないので、月が変わっても日を選んでも読み直しにならない。
    public func monthWeekDays(at index: Int) -> [MonthDayState] {
        let today = self.today
        let timeline = weekTimeline
        return timeline.days(inWeek: index).enumerated().map { column, day in
            // 週の行は週の開始曜日から並ぶので、曜日は列から求められる（1 が日曜、7 が土曜）。暦で日ごとに求めない。
            let weekday = (timeline.firstWeekday - 1 + column) % 7 + 1
            return MonthDayState(
                day: day,
                isToday: day == today,
                isSelectable: timeline.isSelectable(day),
                weekdayKind: weekday == 1 ? .sunday : weekday == 7 ? .saturday : .weekday
            )
        }
    }

    /// 月表示の覆いの層が読む、番号の週の中で表示月の外にある列。表示月と週の並びだけを読む。
    ///
    /// 週の並びを作り直すと、同じ番号の週が別の 7 日を指すので、`clockRevision` も読む。
    public func outOfMonthColumns(inWeek index: Int) -> [Int] {
        _ = clockRevision
        let displayedMonth = self.displayedMonth
        let days = weekTimeline.days(inWeek: index)
        return days.indices.filter { !displayedMonth.contains(days[$0]) }
    }

    /// 月表示の予定の層が読む、番号の週の予定の配置。
    ///
    /// 予定、カレンダーの色、週の並び、暦だけに依存し、選択日、表示月、今日を読まない。
    /// 予定の過去かどうかは現在時刻で決まるので、日付の変化（`clockRevision`）で作り直す。選べない日には予定がない。
    public func monthWeekLayout(at index: Int) -> MonthWeekLayout {
        _ = clockRevision
        let stamp = monthLayoutStamp
        return monthLayoutCache.layout(at: index, stamp: stamp) { makeMonthWeekLayout(at: index) }
    }

    /// 予定の配置の記憶を捨てる印。読み込み、日付の変化、週の並びの作り直し、1 分の経過で変わる。
    var monthLayoutStamp: MonthWeekLayoutCache.Stamp {
        MonthWeekLayoutCache.Stamp(
            dataRevision: dataRevision, clockRevision: clockRevision, timeline: weekTimeline,
            minute: Int(dateProvider.now.timeIntervalSinceReferenceDate / 60)
        )
    }

    /// 月表示の予定の配置の記憶の状態。テスト用。
    var monthLayoutCacheForTesting: MonthWeekLayoutCache { monthLayoutCache }

    private func makeMonthWeekLayout(at index: Int) -> MonthWeekLayout {
        let timeline = weekTimeline
        let days = timeline.days(inWeek: index)
        var weekEvents: [CalendarDay: [CalendarEvent]] = [:]
        for day in days where timeline.isSelectable(day) {
            if let events = eventsByDay[day] { weekEvents[day] = events }
        }
        let colors = calendarColors
        return MonthWeekLayout(
            days: days,
            eventsByDay: weekEvents,
            color: { colors[$0.calendarIdentity] },
            now: dateProvider.now,
            calendar: dateProvider.calendar,
            formatter: formatter
        )
    }

    /// 月表示で VoiceOver に見せる、番号の週の 7 日のボタンの内容。選択日、週の並び、暦だけを読み、表示月と今日は読まない。
    ///
    /// 週の並びは観測の対象にならないので、作り直したとき（`clockRevision` が進んだとき）に読み直すよう `clockRevision` を読む。
    public func dayAccessibility(inWeek index: Int) -> [DayAccessibilityState] {
        _ = clockRevision
        let selectedDay = self.selectedDay
        let timeline = weekTimeline
        return timeline.days(inWeek: index).map { day in
            DayAccessibilityState(
                day: day, label: currentFormatter.dayHeader(day),
                isSelected: day == selectedDay, isSelectable: timeline.isSelectable(day)
            )
        }
    }

    /// 番号の週の中で、選択日の列。選択日がその週になければ `nil`。選択日と週の並びだけを読む。
    ///
    /// 週の並びを作り直すと、同じ番号の週が別の 7 日を指すので、`clockRevision` も読む。
    public func selectedColumn(inWeek index: Int) -> Int? {
        _ = clockRevision
        let selectedDay = self.selectedDay
        return weekTimeline.days(inWeek: index).firstIndex(of: selectedDay)
    }

    /// 番号の週の `column` 列の日。範囲外なら `nil`。
    public func day(inWeek index: Int, column: Int) -> CalendarDay? {
        let days = weekTimeline.days(inWeek: index)
        return days.indices.contains(column) ? days[column] : nil
    }

    /// 番号の週の `column` 列の日の見出し（VoiceOver に読ませる文）。範囲外なら空文字。
    public func dayHeader(inWeek index: Int, column: Int) -> String {
        day(inWeek: index, column: column).map(currentFormatter.dayHeader) ?? ""
    }

    /// 月表示の日の欄に出す、選択日の 1 日のスケジュール。選択日、その日の予定、読み込みの状態だけを読み、表示月は読まない。
    public var selectedDaySchedule: DayScheduleState { daySchedule(for: selectedDay) }

    /// 日の欄に出す、`day` の 1 日のスケジュール。
    ///
    /// 時刻付きの予定は、その日の範囲（0 時と 24 時で切る）の分で表し、重なりの配置は `DayTimelineLayout` が決める。
    /// 終日の予定と、その日が丸ごと埋まる時刻付きの予定は、`allDay` にまとめる。
    public func daySchedule(for day: CalendarDay) -> DayScheduleState {
        _ = clockRevision
        let calendar = dateProvider.calendar
        let today = self.today
        let now = dateProvider.now
        let events = eventsByDay[day] ?? []
        let dayStart = day.startDate(in: calendar)
        let dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)

        func minute(_ date: Date) -> Int {
            if date >= dayEnd { return DayTimelineLayout<CalendarEvent.Identity>.minutesPerDay }
            if date <= dayStart { return 0 }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        func item(of event: CalendarEvent) -> DayScheduleItem {
            DayScheduleItem(
                id: event.id,
                color: calendarColors[event.calendarIdentity],
                title: event.title.isEmpty ? "(タイトルなし)" : event.title,
                timeText: timeText(of: event.schedule, on: day),
                calendarName: snapshot.calendar(for: event.calendarIdentity)?.name,
                isPast: event.schedule.hasEnded(on: day, at: now, calendar: calendar)
            )
        }

        var allDay: [DayScheduleItem] = []
        var timed: [(item: DayScheduleItem, entry: DayTimelineLayout<CalendarEvent.Identity>.Entry)] = []
        for event in events {
            switch event.schedule.span(on: day, calendar: calendar) {
            case .allDay, .entireDay:
                allDay.append(item(of: event))
            case .withinDay(let start, let end):
                timed.append((item(of: event), .init(id: event.id, startMinute: minute(start), endMinute: minute(end))))
            case .startsOnDay(let start):
                timed.append((item(of: event), .init(id: event.id, startMinute: minute(start), endMinute: DayTimelineLayout<CalendarEvent.Identity>.minutesPerDay)))
            case .endsOnDay(let end):
                timed.append((item(of: event), .init(id: event.id, startMinute: 0, endMinute: minute(end))))
            }
        }
        let items = Dictionary(timed.map { ($0.item.id, $0.item) }, uniquingKeysWith: { first, _ in first })
        let layout = DayTimelineLayout(entries: timed.map(\.entry))
        let blocks = layout.blocks.compactMap { block -> DayScheduleBlock? in
            guard let item = items[block.id] else { return nil }
            return DayScheduleBlock(
                item: item, startMinute: block.startMinute, endMinute: block.displayEndMinute,
                column: block.column, columnCount: block.columnCount
            )
        }
        let isToday = day == today
        let currentMinute = isToday ? minute(now) : nil
        let unavailable: Bool = switch phase {
        case .guide, .failed: true
        case .idle, .loading, .loaded: false
        }
        return DayScheduleState(
            day: day,
            title: currentFormatter.dayHeader(day),
            relativeLabel: isToday ? "今日" : day == today.adding(days: 1, calendar: calendar) ? "明日" : nil,
            isToday: isToday,
            isLoaded: loadedRange?.contains(day) ?? false,
            isUnavailable: unavailable,
            allDay: allDay,
            blocks: blocks,
            currentMinute: currentMinute,
            scrollMinute: DayScheduleScroll.targetMinute(
                currentMinute: currentMinute, firstTimedStartMinute: blocks.first?.startMinute
            )
        )
    }

    /// 予定一覧に並べる日の範囲。マス目が表示できる月の日だけで、選択日にも読み込みにも依存しない。
    public var agendaRange: DayRange { weekTimeline.selectableDayRange }

    /// 予定一覧の日数。
    public var agendaDayCount: Int { weekTimeline.dayCount }

    /// 一覧の最初の日から数えた番号の日。範囲外なら `nil`。
    public func agendaDay(at index: Int) -> CalendarDay? { weekTimeline.day(at: index) }

    /// 一覧の最初の日から数えた `day` の番号。範囲外なら `nil`。
    public func agendaIndex(of day: CalendarDay) -> Int? { weekTimeline.dayIndex(of: day) }

    /// 番号の日の表示内容。セクションの View が自分の日だけを読むための入口で、全日分の配列は作らない。範囲外なら `nil`。
    public func agendaSection(at index: Int) -> AgendaSectionState? {
        guard let day = weekTimeline.day(at: index) else { return nil }
        let calendar = dateProvider.calendar
        let today = self.today
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let now = dateProvider.now
        return AgendaSectionState(
            day: day,
            title: currentFormatter.dayHeader(day),
            relativeLabel: day == today ? "今日" : day == tomorrow ? "明日" : nil,
            rows: (eventsByDay[day] ?? []).map { row(for: $0, on: day, now: now) },
            isLoaded: loadedRange?.contains(day) ?? false
        )
    }

    /// 詳細を表示している予定の内容。読み直した後の予定の内容で作るため、古い内容は残らない。
    public var eventDetail: EventDetailState? {
        detailEventID.flatMap(event(for:)).map(detail(for:))
    }

    /// 例は `最終更新 12:00`。
    public var lastUpdatedText: String? {
        lastUpdated.map { "最終更新 \(formatter.time($0))" }
    }

    /// 設定画面で変更があったことを検出するための値。View が変化を監視して読み込み直す。
    public var changeRevision: Int { changeNotifier.revision }

    public var isLoading: Bool { phase == .loading }

    /// 一度も読み込みを終えておらず、予定一覧の代わりに読み込み中の表示を出す状態か。
    public var isAwaitingFirstLoad: Bool { phase != .loaded && lastUpdated == nil }

    // MARK: - 取得範囲

    /// 予定を取得する範囲。月のマス目と予定一覧が表示できる全範囲（`agendaRange`）である。
    ///
    /// 一度の読み込みで全範囲を取得するので、スクロールや日の選択、月の移動では読み込み直さない。
    public var fetchRange: DayRange { agendaRange }

    // MARK: - 操作

    public func showPreviousMonth() { move(to: displayedMonth.previous) }

    public func showNextMonth() { move(to: displayedMonth.next) }

    public func showToday() {
        closeDetail()
        let today = self.today
        displayedMonth = today.calendarMonth
        requestGridScroll()
        changeSelectedDay(to: today)
        loadIfNeeded()
    }

    /// 日を選ぶ。表示月以外の日を選んだら、その月に移動して選択し、マス目をその月へスクロールする。
    /// 表示月の日を選んだときは、マス目をスクロールしない（利用者が見ている位置を動かさない）。
    /// マス目が表示できない月の日（端の行に見える薄い色の日）は選ばない。
    public func select(_ day: CalendarDay) {
        guard weekTimeline.isSelectable(day) else { return }
        closeDetail()
        if displayedMonth != day.calendarMonth {
            displayedMonth = day.calendarMonth
            requestGridScroll()
        }
        changeSelectedDay(to: day)
        loadIfNeeded()
    }

    /// 利用者のマス目のスクロールで、一番上の週が変わったときに呼ぶ。
    ///
    /// 表示月だけを、見えている週の中央の週の月に合わせる。予定は読み込み直さない。選択日は変えず、予定一覧もスクロールさせず、
    /// 詳細も閉じない。マス目のスクロールは要求しない（要求すると、スクロールと表示月が互いを更新し続ける）。
    public func gridDidScroll(toTopWeek week: Int) {
        let month = clampToShowable(weekTimeline.displayedMonth(topWeek: week))
        guard month != displayedMonth else { return }
        displayedMonth = month
    }

    /// 利用者のスクロールで、一覧の一番上の日が変わったときに呼ぶ。
    ///
    /// 選択日と表示月を `day` に合わせる。予定は読み込み直さない。一覧のスクロールは要求しない（要求すると、
    /// スクロールと選択日が互いを更新し続ける）。詳細は閉じない。詳細を表示している間は一覧が見えないため、何もしない。
    public func agendaDidScroll(toTopDay day: CalendarDay) {
        guard detailEventID == nil, agendaRange.contains(day) else { return }
        if selectedDay != day { selectedDay = day }
        if displayedMonth != day.calendarMonth {
            displayedMonth = day.calendarMonth
            requestGridScroll()
        }
    }

    /// 日付・タイムゾーン・地域設定が変わったときに呼ぶ。今日が変わっていれば選択日と表示月を今日に戻し、読み込み直す。
    public func systemCalendarDidChange() {
        clockRevision += 1
        monthImageStore.removeAll()
        let didRebuildTimeline = rebuildTimelineIfNeeded()
        if !resetToTodayIfDayChanged(), didRebuildTimeline {
            // 週の番号と日の番号が振り直されたので、選択日が選べる範囲に収まるようにしてから、
            // 表示月と選択日の位置に、マス目と一覧を合わせ直す。
            clampSelectionToSelectableRange()
            requestGridScroll()
            requestAgendaScroll(to: selectedDay)
        }
        reload()
    }

    /// ポップオーバーを開いたときに呼ぶ。古くなければ読み込み直さない。
    ///
    /// 前回の表示から日付が変わっていたら、選択日と表示月を今日に戻して必ず読み込む。
    ///
    /// 読み直さない場合でも、サーバーとの同期は求める。
    public func popoverDidAppear() {
        closeDetail()
        closeCalendarFilter()
        requestSourceSync()
        if resetToTodayIfDayChanged() {
            reload()
            return
        }
        // 読み込み中は、新しく始めても同じ結果を取り直すだけで、進行中の読み込みを捨てることになる。
        if isLoadInFlight, changeRevision == observedRevision { return }
        if let lastUpdated, phase == .loaded,
           dateProvider.now.timeIntervalSince(lastUpdated) < Self.staleInterval,
           changeRevision == observedRevision {
            return
        }
        reload()
    }

    /// ポップオーバーのウインドウが画面に取り付いたときに呼ぶ。以後、このウインドウが key になったときだけ開いたとみなす。
    ///
    /// - Parameters:
    ///   - windowID: ウインドウの識別子。ウインドウから外れたときは `nil`。
    ///   - isKey: 取り付いた時点でそのウインドウが key か。
    public func popoverWindowDidChange(_ windowID: ObjectIdentifier?, isKey: Bool) {
        popoverWindowID = windowID
        if windowID != nil, isKey { popoverDidAppear() }
    }

    /// いずれかのウインドウが key になったときに呼ぶ。ポップオーバー自身のウインドウのときだけ、開いたとみなす。
    public func windowDidBecomeKey(_ windowID: ObjectIdentifier) {
        guard windowID == popoverWindowID else { return }
        popoverDidAppear()
    }

    /// 読み込みを始める。進行中の読み込みはキャンセルし、その結果は反映しない。表示するカレンダーの一覧を開いていれば、一覧も読み直す。
    public func reload() {
        startLoad()
        if isCalendarFilterOpen { refreshCalendarFilter() }
    }

    /// サーバーとの同期を OS に求めてから、読み込み直す。更新ボタンと、スリープからの復帰で呼ぶ。
    public func refresh() {
        requestSourceSync()
        reload()
    }

    /// サーバーとの同期を OS に求める。読み込みを待たせないよう、別の Task に投げる。新しいデータは変更通知で届く。
    private func requestSourceSync() {
        let refreshCalendarSources = refreshCalendarSources
        Task { await refreshCalendarSources.execute() }
    }

    /// 変更通知を受けたときの読み直し。読み込み中は取り消さず、終わってから 1 回だけ読み直す。
    ///
    /// 取得は取り消せないため、通知のたびに取り消して始め直すと、通知の数だけ取得が直列に走る。
    private func reloadForStoreChange() {
        if isLoadInFlight {
            needsReloadAfterLoad = true
        } else {
            reload()
        }
    }

    /// 予定だけを読み込み直す。表示するカレンダーの切り替えのように、一覧を自分で更新した変更で使う。
    private func startLoad() {
        loadTask?.cancel()
        loadGeneration += 1
        // 新しい読み込みは、印を付けた通知より後に始まるため、その通知の分も含む。
        needsReloadAfterLoad = false
        observedRevision = changeNotifier.revision
        isLoadInFlight = true
        let range = fetchRange
        loadingRange = range
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            await self?.performLoad(generation: generation, range: range)
            self?.loadDidFinish(generation: generation)
        }
    }

    /// 最新の読み込みの完了を待つ。テストと、完了後に処理を続けたい呼び出し側のためにある。
    public func waitForLoad() async {
        await loadTask?.value
    }

    /// 案内のボタンを押したときの操作。許可の状態により、許可を求めるか、システム設定を開く。
    public func perform(_ guide: CalendarAccessGuide) async {
        switch guide {
        case .notDetermined:
            await requestAccess()
        case .denied:
            openSystemSettings.execute(.calendarPrivacy)
        case .noCalendars:
            openSystemSettings.execute(.internetAccounts)
        }
    }

    /// 許可を求め、結果に合わせて読み込み直す。求めている間は何もしない。
    private func requestAccess() async {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        do {
            try await requestCalendarAccess.execute()
        } catch {
            phase = .failed(UserFacingMessage.text(for: error))
            return
        }
        // 設定画面にも許可の結果を伝える。自分で読み直すため、自分の通知では読み直さない。
        changeNotifier.notifyChange()
        reload()
    }

    /// 設定画面など他の画面から変更が通知されていれば読み込み直す。自分で起こした変更では読み込み直さない。
    public func reloadIfChangedElsewhere() {
        if changeRevision != observedRevision { reload() }
    }

    public func openMeeting(of row: AgendaRowState) {
        guard let url = event(for: row.id)?.meetingURL else { return }
        urlOpener.open(url)
    }

    /// 予定一覧の行の予定を、詳細として表示する。読み込み済みの予定にない行では何もしない。
    public func showDetail(of row: AgendaRowState) {
        showDetail(of: row.id)
    }

    /// 予定を詳細として表示する。読み込み済みの予定にないときは何もしない。表示するカレンダーの一覧は閉じる。
    public func showDetail(of id: CalendarEvent.Identity) {
        guard event(for: id) != nil else { return }
        isCalendarFilterOpen = false
        detailEventID = id
    }

    /// 詳細を閉じる。月表示は日の欄のスケジュールに、コンパクト表示は予定一覧に戻る。
    public func closeDetail() {
        detailEventID = nil
    }

    /// 月表示でマス目の日（予定のない場所と「他 N 件」）を押したときの操作。その日を選び、日の欄をその日のスケジュールにする。
    ///
    /// 詳細と、表示するカレンダーの一覧を閉じる。選べない日では何もしない。日を選ぶ規則は `select(_:)` と同じである。
    public func showSchedule(of day: CalendarDay) {
        guard weekTimeline.isSelectable(day) else { return }
        isCalendarFilterOpen = false
        select(day)
    }

    /// 表示モードを変えて保存する。同じモードなら何もしない。
    ///
    /// 詳細を閉じる。予定は読み込み直さず、表示月と選択日も変えない。表示するカレンダーの一覧は開いたままにする。
    public func setDisplayMode(_ mode: CalendarDisplayMode) {
        guard mode != displayMode else { return }
        closeDetail()
        displayMode = mode
        saveDisplayMode.execute(mode)
    }

    /// 詳細の中のリンクと「参加」ボタンの URL を開く。http と https 以外は開かない。
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard LinkedText.isWebURL(url) else { return false }
        return urlOpener.open(url)
    }

    // MARK: - 表示するカレンダーの一覧

    /// 表示するカレンダーの一覧を開く。詳細は閉じる。一覧は読み込む。
    public func openCalendarFilter() {
        closeDetail()
        isCalendarFilterOpen = true
        calendarFilterError = nil
        if calendarFilterPhase != .loaded { calendarFilterPhase = .loading }
        refreshCalendarFilter()
    }

    public func closeCalendarFilter() {
        isCalendarFilterOpen = false
        calendarFilterError = nil
    }

    public func toggleCalendarFilter() {
        if isCalendarFilterOpen { closeCalendarFilter() } else { openCalendarFilter() }
    }

    /// 一覧の読み込みの完了を待つ。テストのためにある。
    public func waitForCalendarFilter() async {
        await calendarFilterTask?.value
    }

    /// カレンダー 1 つの表示と非表示を切り替える。
    public func setVisibility(of calendar: UserCalendar.Identity, isVisible: Bool) async {
        await applyVisibility(to: [calendar], isVisible: isVisible)
    }

    /// アカウントのカレンダーすべての表示と非表示を、1 回の保存で切り替える。
    public func setVisibility(ofAccount account: AccountID, isVisible: Bool) async {
        let identities = calendarFilterSections.first { $0.id == account }?.items.map(\.id) ?? []
        await applyVisibility(to: identities, isVisible: isVisible)
    }

    /// 先に一覧の表示を変え、保存できたら設定画面に伝えて予定を読み込み直す。失敗したら元に戻す。
    ///
    /// 一覧は読み直さない。続けて切り替えたチェックを、読み直した古い内容が上書きしないため。
    private func applyVisibility(to identities: [UserCalendar.Identity], isVisible: Bool) async {
        let current = Dictionary(
            calendarFilterSections.flatMap(\.items).map { ($0.id, $0.isVisible) }, uniquingKeysWith: { first, _ in first }
        )
        let changing = identities.filter { current[$0] == !isVisible }
        guard !changing.isEmpty else { return }
        calendarFilterGeneration += 1
        calendarFilterError = nil
        setFilterVisibility(of: changing, to: isVisible)
        do {
            try await setCalendarVisibility.execute(calendars: changing, isVisible: isVisible)
        } catch {
            calendarFilterGeneration += 1
            setFilterVisibility(of: changing, to: !isVisible)
            calendarFilterError = UserFacingMessage.text(for: error)
            return
        }
        // 設定画面にも伝える。予定は自分で読み込み直すので、先に通知を送って、自分の通知では読み込み直さないようにする。
        changeNotifier.notifyChange()
        startLoad()
    }

    private func setFilterVisibility(of identities: [UserCalendar.Identity], to isVisible: Bool) {
        let targets = Set(identities)
        calendarFilterSections = calendarFilterSections.map { section in
            CalendarAccountSection(
                account: section.account,
                items: section.items.map { item in
                    targets.contains(item.id) ? CalendarListItem(calendar: item.calendar, isVisible: isVisible) : item
                }
            )
        }
    }

    /// 一覧を読み込む。読み込みの間に切り替えがあったり、一覧を閉じたりしたら、結果は捨てる。
    private func refreshCalendarFilter() {
        calendarFilterGeneration += 1
        let generation = calendarFilterGeneration
        calendarFilterTask = Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await listCalendars.execute()
                guard generation == calendarFilterGeneration, isCalendarFilterOpen else { return }
                calendarFilterSections = CalendarAccountSection.sections(accounts: list.accounts, items: list.items)
                calendarFilterPhase = list.items.isEmpty ? .unavailable(CalendarAccessGuide.noCalendars.message) : .loaded
            } catch {
                guard generation == calendarFilterGeneration, isCalendarFilterOpen else { return }
                calendarFilterSections = []
                calendarFilterPhase = .unavailable(UserFacingMessage.text(for: error))
            }
        }
    }

    // MARK: - 内部

    private var observedRevision = 0

    /// 今日が前回の確認から変わっていれば、選択日と表示月を今日に戻して `true` を返す。
    @discardableResult
    private func resetToTodayIfDayChanged() -> Bool {
        let today = self.today
        guard today != lastSeenToday else { return false }
        closeDetail()
        lastSeenToday = today
        // 今日を含む週が変わっていたら、今日を中心に週の並びを作り直す。以下の要求は、作り直した並びの番号で出す。
        rebuildTimelineIfTodayWeekChanged(today: today)
        displayedMonth = today.calendarMonth
        requestGridScroll()
        changeSelectedDay(to: today)
        return true
    }

    private func move(to month: CalendarMonth) {
        // マス目の週の並びの外へは進めない。
        guard weekTimeline.canShow(month) else { return }
        closeDetail()
        displayedMonth = month
        requestGridScroll()
        // 今日を含む月なら今日、それ以外は月の初日を選ぶ。
        changeSelectedDay(to: month.contains(today) ? today : month.firstDay)
        loadIfNeeded()
    }

    /// 現在の週の並び。週の開始曜日が変わっていれば作り直す。
    private var weekTimeline: WeekTimeline {
        _ = rebuildTimelineIfNeeded()
        return timeline
    }

    /// 週の開始曜日が変わっていたら、今日を含む週を基準に週の並びを作り直して `true` を返す。
    @discardableResult
    private func rebuildTimelineIfNeeded() -> Bool {
        let firstWeekday = dateProvider.calendar.firstWeekday
        guard timeline.firstWeekday != firstWeekday else { return false }
        timeline = Self.makeTimeline(today: today, firstWeekday: firstWeekday)
        return true
    }

    /// 今日を含む週が、並びを作ったときの週と変わっていたら、今日を中心に作り直す。長く起動したままでも、今日が範囲に残る。
    private func rebuildTimelineIfTodayWeekChanged(today: CalendarDay) {
        guard timeline.weekIndex(containing: today) != timeline.todayWeekIndex else { return }
        timeline = Self.makeTimeline(today: today, firstWeekday: dateProvider.calendar.firstWeekday)
    }

    /// 月を、マス目が表示できる最初の月から最後の月の間に収める。
    private func clampToShowable(_ month: CalendarMonth) -> CalendarMonth {
        let range = weekTimeline.selectableDayRange
        let first = range.start.calendarMonth
        let last = range.end.adding(days: -1, calendar: dateProvider.calendar).calendarMonth
        return min(max(month, first), last)
    }

    /// 選択日が選べる範囲の外なら、範囲の端の日に寄せ、表示月も合わせる。
    private func clampSelectionToSelectableRange() {
        let range = weekTimeline.selectableDayRange
        if !range.contains(selectedDay) {
            selectedDay = selectedDay < range.start ? range.start : range.end.adding(days: -1, calendar: dateProvider.calendar)
        }
        displayedMonth = clampToShowable(displayedMonth)
    }

    /// 表示月の最初の週を一番上にするよう、マス目のスクロールを求める。同じ月を続けて求めても別の要求として出す。
    private func requestGridScroll() {
        guard let week = weekTimeline.firstWeekIndex(of: displayedMonth) else { return }
        gridScrollRequest = GridScrollRequest(weekIndex: week, serial: (gridScrollRequest?.serial ?? 0) + 1)
    }

    /// ViewModel の操作で選択日を変える。一覧のスクロールを要求する。
    ///
    /// 同じ日を続けて選んでも要求は出す（利用者が一覧を動かした後でも、選択日の位置に戻すため）。
    private func changeSelectedDay(to day: CalendarDay) {
        if selectedDay != day { selectedDay = day }
        requestAgendaScroll(to: day)
    }

    private func requestAgendaScroll(to day: CalendarDay) {
        agendaScrollRequest = AgendaScrollRequest(day: day, serial: (agendaScrollRequest?.serial ?? 0) + 1)
    }

    /// 全範囲が読み込み済みの範囲に収まっていれば、読み込み直さない。
    /// 進行中の読み込みが全範囲を含んでいるときも、取り消さずに待つ。
    private func loadIfNeeded() {
        let required = fetchRange
        if let loadedRange, phase == .loaded, covers(loadedRange, required) { return }
        if isLoadInFlight, let loadingRange, covers(loadingRange, required) { return }
        reload()
    }

    private func covers(_ outer: DayRange, _ inner: DayRange) -> Bool {
        outer.start <= inner.start && inner.end <= outer.end
    }

    private func performLoad(generation: Int, range: DayRange) async {
        guard isCurrent(generation) else { return }
        phase = .loading

        do {
            let newSnapshot = try await loadAgenda.execute(range: range)
            guard isCurrent(generation) else { return }
            setSnapshot(newSnapshot)
            loadedRange = range
            lastUpdated = dateProvider.now
            phase = .loaded
            // 読み直した結果に詳細の予定がなければ、一覧に戻る。
            if let detailEventID, event(for: detailEventID) == nil { closeDetail() }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(generation) else { return }
            if let guide = (error as? CalendarAccessError).map(CalendarAccessGuide.init) {
                finish(generation, phase: .guide(guide))
                return
            }
            phase = .failed(UserFacingMessage.text(for: error))
            loadedRange = nil
            closeDetail()
        }
    }

    /// 取り消されて世代が進んだ読み込みは、新しい読み込みの進行中の印を消さない。
    private func loadDidFinish(generation: Int) {
        if generation == loadGeneration {
            isLoadInFlight = false
            loadingRange = nil
            if needsReloadAfterLoad { reload() }
        }
    }

    private func finish(_ generation: Int, phase: Phase) {
        guard isCurrent(generation) else { return }
        self.phase = phase
        setSnapshot(.empty)
        loadedRange = nil
        closeDetail()
    }

    private func setSnapshot(_ newSnapshot: AgendaSnapshot) {
        snapshot = newSnapshot
        dataRevision += 1
        monthImageStore.removeAll()
        eventsByDay = Dictionary(newSnapshot.days.map { ($0.day, $0.events) }, uniquingKeysWith: { first, _ in first })
        calendarColors = Dictionary(newSnapshot.calendars.map { ($0.id, $0.color) }, uniquingKeysWith: { first, _ in first })
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == loadGeneration && !Task.isCancelled
    }

    private func event(for identity: CalendarEvent.Identity) -> CalendarEvent? {
        for agenda in snapshot.days {
            if let event = agenda.events.first(where: { $0.id == identity }) { return event }
        }
        return nil
    }

    private func weekdayKind(of day: CalendarDay, formatter: CalendarFormatter) -> DayCellState.WeekdayKind {
        switch formatter.weekday(of: day) {
        case 1: .sunday
        case 7: .saturday
        default: .weekday
        }
    }

    private func row(for event: CalendarEvent, on day: CalendarDay, now: Date) -> AgendaRowState {
        let calendar = dateProvider.calendar
        return AgendaRowState(
            id: event.id,
            color: snapshot.calendar(for: event.calendarIdentity)?.color,
            timeText: timeText(of: event.schedule, on: day),
            title: event.title.isEmpty ? "(タイトルなし)" : event.title,
            location: event.location.flatMap { $0.isEmpty ? nil : $0 },
            isPast: event.schedule.hasEnded(on: day, at: now, calendar: calendar),
            hasMeetingURL: event.meetingURL != nil
        )
    }

    private func detail(for event: CalendarEvent) -> EventDetailState {
        let calendar = snapshot.calendar(for: event.calendarIdentity)
        return EventDetailState(
            id: event.id,
            color: calendar?.color,
            title: event.title.isEmpty ? "(タイトルなし)" : event.title,
            dateText: formatter.scheduleText(event.schedule),
            calendarName: calendar?.name,
            accountName: snapshot.account(for: event.accountID)?.name,
            location: event.location,
            meetingURL: event.meetingURL,
            detailURL: event.detailURL,
            attendanceText: event.attendance.displayText,
            participants: event.participants.enumerated().map { index, participant in
                ParticipantRowState(
                    id: index,
                    displayName: participant.displayName,
                    emailAddress: participant.name == nil ? nil : participant.emailAddress,
                    isOrganizer: participant.isOrganizer,
                    isCurrentUser: participant.isCurrentUser,
                    attendance: participant.attendance,
                    attendanceText: participant.attendance.displayText
                )
            },
            notes: event.notes.map(LinkedText.attributed)
        )
    }

    private func timeText(of schedule: EventSchedule, on day: CalendarDay) -> String {
        switch schedule.span(on: day, calendar: dateProvider.calendar) {
        case .allDay, .entireDay: "終日"
        case .endsOnDay(let end): "〜\(formatter.time(end))"
        case .startsOnDay(let start): "\(formatter.time(start))〜"
        case .withinDay(let start, let end): "\(formatter.time(start))〜\(formatter.time(end))"
        }
    }

    // `WeekTimeline` の生成は、引数が常に妥当なため失敗しない。失敗はプログラミングエラーとして扱う。
    private static func makeTimeline(today: CalendarDay, firstWeekday: Int) -> WeekTimeline {
        do {
            return try WeekTimeline(today: today, firstWeekday: firstWeekday)
        } catch {
            preconditionFailure("週の並びを作れなかった: \(error)")
        }
    }
}
