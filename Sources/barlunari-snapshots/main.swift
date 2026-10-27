import AppKit
import BarlunariApplication
import BarlunariDomain
import BarlunariPresentation
import BarlunariPreviewSupport
import SwiftUI

// View を PNG に書き出す。ウィンドウは画面に出さず、オフスクリーンの NSWindow の中で描く。
// 利用者のカーソルとフォーカスを奪わないよう、前面化や activate は呼ばない。

/// 何も流れない `AsyncStream` を待ち続け、決して戻らない。`continuation` を保持して、ストリームが閉じるのを防ぐ。
func neverReturn() async {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    for await _ in stream {}
    continuation.finish()
}

/// 結果を返さずに止められる予定のリポジトリ。読み込み中の見た目を描くために使う。
actor SnapshotEventRepository: CalendarEventRepository {
    private let base: InMemoryCalendarEventRepository
    private var isSuspended = false

    init(events: [CalendarEvent], error: (any Error)?) {
        base = InMemoryCalendarEventRepository(events: events, error: error)
    }

    /// 以後の取得は、結果を返さず待ち続ける。
    func suspendFutureRequests() { isSuspended = true }

    func events(in interval: DateInterval, calendars: Set<UserCalendar.Identity>) async throws -> [CalendarEvent] {
        if isSuspended {
            await neverReturn()
        }
        return try await base.events(in: interval, calendars: calendars)
    }
}

/// 組み立て済みの ViewModel 群。状態ごとに作り直す。
@MainActor
struct Fixture {
    let popover: CalendarPopoverViewModel
    let settings: SettingsViewModel
    let events: SnapshotEventRepository

    init(
        status: CalendarAuthorizationStatus = .fullAccess,
        accounts: [UserAccount] = SampleData.accounts,
        calendars: [UserCalendar] = SampleData.calendars,
        eventError: (any Error)? = nil,
        events sampleEvents: [CalendarEvent] = SampleData.events,
        displayMode: CalendarDisplayMode = .compact
    ) {
        let dateProvider = FixedDateProvider()
        let authorizer = FakeCalendarAccessAuthorizer(status: status)
        let calendarRepository = InMemoryCalendarRepository(accounts: accounts, calendars: calendars)
        let eventRepository = SnapshotEventRepository(events: sampleEvents, error: eventError)
        events = eventRepository
        let visibility = InMemoryCalendarVisibilityRepository()
        let launchAtLogin = FakeLaunchAtLoginService(isEnabled: true)
        let requestAccess = RequestCalendarAccessUseCase(authorizer: authorizer)
        let openSystemSettings = OpenSystemSettingsUseCase(opener: FakeSystemSettingsOpener())
        let notifier = DataChangeNotifier()
        let displayModeStore = InMemoryDisplayModeStore(mode: displayMode)

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
            refreshCalendarSources: RefreshCalendarSourcesUseCase(refresher: FakeCalendarSourceRefresher()),
            dateProvider: dateProvider,
            urlOpener: FakeURLOpener(),
            changeNotifier: notifier,
            loadDisplayMode: LoadDisplayModeUseCase(store: displayModeStore),
            saveDisplayMode: SaveDisplayModeUseCase(store: displayModeStore),
            listCalendars: ListCalendarsUseCase(
                authorizer: authorizer, calendarRepository: calendarRepository, visibilityRepository: visibility
            ),
            setCalendarVisibility: SetCalendarVisibilityUseCase(visibilityRepository: visibility),
            workspaceNotificationCenter: NotificationCenter()
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
            changeNotifier: notifier
        )
    }
}

/// 月表示の大きさを決める画面の可視領域。実行する機械の画面に依らず、同じ大きさで出す。
let snapshotVisibleFrame = CGRect(x: 0, y: 0, width: 2056, height: 1215)

enum SnapshotError: Error {
    case renderFailed(String)
}

/// `view` を、画面に出さないウィンドウの中で描いて PNG にする。
@MainActor
func render(_ view: some View, appearance: NSAppearance.Name, to url: URL) async throws {
    // cacheDisplay はウィンドウの背景を含まないため、背景は View の側に敷く。
    // SwiftUI の配色は NSApp の外観に従うので、描く間だけ外観を切り替える。
    NSApplication.shared.appearance = NSAppearance(named: appearance)
    let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
    hosting.appearance = NSAppearance(named: appearance)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.appearance = NSAppearance(named: appearance)
    window.backgroundColor = .windowBackgroundColor
    window.contentView = hosting

    // onGeometryChange などの状態更新を反映させるため、ランループを少し回してから大きさを決める。
    for _ in 0..<3 {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        window.setContentSize(size)
        hosting.frame = NSRect(origin: .zero, size: size)
        await pump(0.05)
    }
    hosting.layoutSubtreeIfNeeded()

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        throw SnapshotError.renderFailed("bitmapImageRep を作れなかった: \(url.lastPathComponent)")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw SnapshotError.renderFailed("PNG に変換できなかった: \(url.lastPathComponent)")
    }
    try data.write(to: url)
    print("\(url.path) \(Int(hosting.bounds.width))x\(Int(hosting.bounds.height))")
}

/// 指定の時間、ランループを回す。この処理はメインアクターの 1 つのジョブの中で動くので、ランループを回すだけでは、
/// View のメインアクターの Task（予定一覧の見出しの合わせ直しなど）が動かない。短く回しては `Task.yield()` で順番を譲る。
@MainActor
func pump(_ seconds: TimeInterval) async {
    let deadline = Date(timeIntervalSinceNow: seconds)
    repeat {
        runLoop(until: min(deadline, Date(timeIntervalSinceNow: 0.001)))
        await Task.yield()
    } while Date() < deadline
}

private func runLoop(until date: Date) {
    RunLoop.current.run(until: date)
}

/// 今日の予定一覧から、タイトルが一致する行の詳細を開く。
@MainActor
func showDetail(titled title: String, in fixture: Fixture) throws {
    let today = fixture.popover.today
    guard let section = fixture.popover.agendaIndex(of: today).flatMap(fixture.popover.agendaSection(at:)),
          let row = section.rows.first(where: { $0.title == title })
    else {
        throw SnapshotError.renderFailed("予定一覧に「\(title)」がない")
    }
    fixture.popover.showDetail(of: row)
}

@MainActor
func runSnapshots(outputDirectory: URL) async throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    // 前回の出力が残ると、いまは出していない状態の古い PNG を見てしまうため、先に消す。
    let existing = try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)
    for file in existing where file.pathExtension == "png" {
        try FileManager.default.removeItem(at: file)
    }
    func output(_ name: String) -> URL { outputDirectory.appendingPathComponent("\(name).png") }

    func popoverView(_ fixture: Fixture, visibleFrame: CGRect = snapshotVisibleFrame) -> some View {
        CalendarPopoverView(viewModel: fixture.popover, openSettings: {}, quit: {}, visibleFrame: visibleFrame)
    }

    // メニューバーのラベル。実際のメニューバーに近い余白を付けて描く。
    for (name, appearance) in [("menubar-label-light", NSAppearance.Name.aqua), ("menubar-label-dark", .darkAqua)] {
        try await render(MenuBarLabelView().padding(12), appearance: appearance, to: output(name))
    }

    // カラーパレットの一覧（全色を役割ごとに並べる）。
    for (name, appearance) in [("palette-light", NSAppearance.Name.aqua), ("palette-dark", .darkAqua)] {
        try await render(CalendarPalettePreviewView(), appearance: appearance, to: output(name))
    }

    // 明るい色、暗い色、低彩度の色を含む多数のカレンダーの月表示。
    for (name, appearance) in [("month-colorful-light", NSAppearance.Name.aqua), ("month-colorful-dark", .darkAqua)] {
        let fixture = Fixture(
            accounts: ColorfulSampleData.accounts, calendars: ColorfulSampleData.calendars,
            events: ColorfulSampleData.events, displayMode: .month
        )
        fixture.popover.reload()
        await fixture.popover.waitForLoad()
        try await render(popoverView(fixture), appearance: appearance, to: output(name))
    }

    // ポップオーバー（読み込み済み）
    for (name, appearance) in [("popover-light", NSAppearance.Name.aqua), ("popover-dark", .darkAqua)] {
        let fixture = Fixture()
        fixture.popover.reload()
        await fixture.popover.waitForLoad()
        try await render(popoverView(fixture), appearance: appearance, to: output(name))
    }

    // 予定の詳細。すべての項目がある予定をライトとダークで、項目が少ない予定をライトで描く。
    for (name, appearance) in [("popover-detail-light", NSAppearance.Name.aqua), ("popover-detail-dark", .darkAqua)] {
        let fixture = Fixture()
        fixture.popover.reload()
        await fixture.popover.waitForLoad()
        try showDetail(titled: "デザインレビュー", in: fixture)
        try await render(popoverView(fixture), appearance: appearance, to: output(name))
    }
    do {
        let fixture = Fixture()
        fixture.popover.reload()
        await fixture.popover.waitForLoad()
        try showDetail(titled: "夕食", in: fixture)
        try await render(popoverView(fixture), appearance: .aqua, to: output("popover-detail-minimal"))
    }

    // ポップオーバー（月曜始まりの別の日を選択した状態）
    do {
        let fixture = Fixture()
        fixture.popover.select(SampleData.day(2026, 10, 27))
        await fixture.popover.waitForLoad()
        try await render(popoverView(fixture), appearance: .aqua, to: output("popover-selected-other-day"))
    }

    // 許可が未決定・拒否・カレンダーなし・エラー。
    let guides: [(String, Fixture)] = [
        ("popover-not-determined", Fixture(status: .notDetermined)),
        ("popover-denied", Fixture(status: .denied)),
        ("popover-no-calendars", Fixture(accounts: [], calendars: [])),
        ("popover-error", Fixture(eventError: CocoaError(.fileReadUnknown))),
    ]
    for (name, fixture) in guides {
        fixture.popover.reload()
        await fixture.popover.waitForLoad()
        try await render(popoverView(fixture), appearance: .aqua, to: output(name))
    }

    // 読み込み済みのあと、読み込み直している状態（「予定はありません」を出さない）。
    let navigating = Fixture()
    navigating.popover.reload()
    await navigating.popover.waitForLoad()
    await navigating.events.suspendFutureRequests()
    navigating.popover.reload()
    while !navigating.popover.isLoading { await Task.yield() }
    try await render(popoverView(navigating), appearance: .aqua, to: output("popover-reloading"))

    // 月表示。入りきらない日、週をまたぐバー、日をまたぐ予定、長いタイトルを含むサンプルで描く。
    func monthFixture(
        status: CalendarAuthorizationStatus = .fullAccess, eventError: (any Error)? = nil
    ) -> Fixture {
        Fixture(status: status, eventError: eventError, events: SampleData.monthViewEvents, displayMode: .month)
    }
    func loadedMonth() async -> Fixture {
        let fixture = monthFixture()
        fixture.popover.reload()
        await fixture.popover.waitForLoad()
        return fixture
    }
    func eventID(titled title: String) throws -> CalendarEvent.Identity {
        guard let event = SampleData.monthViewEvents.first(where: { $0.title == title }) else {
            throw SnapshotError.renderFailed("サンプルに「\(title)」がない")
        }
        return event.id
    }
    for (name, appearance) in [("month-light", NSAppearance.Name.aqua), ("month-dark", .darkAqua)] {
        try await render(popoverView(await loadedMonth()), appearance: appearance, to: output(name))
    }
    for (name, appearance) in [("month-detail-light", NSAppearance.Name.aqua), ("month-detail-dark", .darkAqua)] {
        let fixture = await loadedMonth()
        fixture.popover.showDetail(of: try eventID(titled: "デザインレビュー"))
        try await render(popoverView(fixture), appearance: appearance, to: output(name))
    }
    func openedCalendarFilter(_ fixture: Fixture) async {
        fixture.popover.reload()
        await fixture.popover.waitForLoad()
        fixture.popover.openCalendarFilter()
        await fixture.popover.waitForCalendarFilter()
        await fixture.popover.setVisibility(of: SampleData.holidayCalendar.id, isVisible: false)
        await fixture.popover.waitForLoad()
    }
    // 狭い画面の 2 列（余白を引いた幅が 3 列の下限に届かない可視領域）。詳細の列を出さず、日の欄で詳細と一覧をスケジュールと入れ替える。
    let twoColumnFrame = CGRect(x: 0, y: 0, width: 1440, height: 1215)
    do {
        let fixture = await loadedMonth()
        try await render(popoverView(fixture, visibleFrame: twoColumnFrame), appearance: .aqua, to: output("month-two-column-light"))
        fixture.popover.showDetail(of: try eventID(titled: "デザインレビュー"))
        try await render(popoverView(fixture, visibleFrame: twoColumnFrame), appearance: .aqua, to: output("month-two-column-detail-light"))
    }
    do {
        let fixture = monthFixture()
        await openedCalendarFilter(fixture)
        try await render(popoverView(fixture, visibleFrame: twoColumnFrame), appearance: .aqua, to: output("month-two-column-calendars-light"))
    }
    // 日の欄。選択日のスケジュール（今日、予定の多い日、重なる予定の日、予定のない日、詳細からの戻り）を描く。
    do {
        // 今日（既定の選択日）。現在時刻の線と、過去の予定の薄め。
        let fixture = await loadedMonth()
        try await render(popoverView(fixture), appearance: .aqua, to: output("month-day-today"))
    }
    do {
        let fixture = await loadedMonth()
        fixture.popover.showSchedule(of: SampleData.day(2026, 10, 22))
        try await render(popoverView(fixture), appearance: .aqua, to: output("month-day-events"))
        fixture.popover.showDetail(of: try eventID(titled: "レビュー"))
        try await render(popoverView(fixture), appearance: .aqua, to: output("month-day-events-detail"))
    }
    for (name, appearance) in [("month-day-overlap-light", NSAppearance.Name.aqua), ("month-day-overlap-dark", .darkAqua)] {
        let fixture = await loadedMonth()
        fixture.popover.showSchedule(of: SampleData.day(2026, 10, 23))
        try await render(popoverView(fixture), appearance: appearance, to: output(name))
    }
    do {
        // 予定のない日。
        let fixture = await loadedMonth()
        fixture.popover.showSchedule(of: SampleData.day(2026, 10, 21))
        try await render(popoverView(fixture), appearance: .aqua, to: output("month-day-events-empty"))
    }
    do {
        // 予定の多い日（密なサンプル）。
        let fixture = Fixture(events: SampleData.denseMonthViewEvents, displayMode: .month)
        fixture.popover.reload()
        await fixture.popover.waitForLoad()
        fixture.popover.showSchedule(of: SampleData.day(2026, 10, 27))
        try await render(popoverView(fixture), appearance: .aqua, to: output("month-day-dense"))
    }
    // 月表示で次の月へ移った状態。
    do {
        let fixture = await loadedMonth()
        fixture.popover.showNextMonth()
        await pump(0.8)
        try await render(popoverView(fixture), appearance: .aqua, to: output("month-next-month"))
    }
    // 案内とエラー。読み込み中の状態（初回）も描く。
    let monthGuides: [(String, Fixture)] = [
        ("month-not-determined", monthFixture(status: .notDetermined)),
        ("month-denied", monthFixture(status: .denied)),
        ("month-error", monthFixture(eventError: CocoaError(.fileReadUnknown))),
    ]
    for (name, fixture) in monthGuides {
        fixture.popover.reload()
        await fixture.popover.waitForLoad()
        try await render(popoverView(fixture), appearance: .aqua, to: output(name))
    }
    do {
        let fixture = monthFixture()
        await fixture.events.suspendFutureRequests()
        fixture.popover.reload()
        while !fixture.popover.isLoading { await Task.yield() }
        try await render(popoverView(fixture), appearance: .aqua, to: output("month-loading"))
    }

    // 表示するカレンダーの一覧。月表示とコンパクト表示を、ライトとダークで描く。
    // 1 アカウントのカレンダーを一部だけ非表示にして、アカウントのチェックボックスの混在の状態も描く。
    for (name, appearance) in [("month-calendars-light", NSAppearance.Name.aqua), ("month-calendars-dark", .darkAqua)] {
        let fixture = monthFixture()
        await openedCalendarFilter(fixture)
        try await render(popoverView(fixture), appearance: appearance, to: output(name))
    }
    for (name, appearance) in [("popover-calendars-light", NSAppearance.Name.aqua), ("popover-calendars-dark", .darkAqua)] {
        let fixture = Fixture()
        await openedCalendarFilter(fixture)
        try await render(popoverView(fixture), appearance: appearance, to: output(name))
    }

    // 設定の一般タブと、2 アカウントのカレンダータブ。
    let settings = Fixture()
    await settings.settings.load()
    for (name, tab) in [("general", SettingsView.Tab.general), ("calendars", .calendars)] {
        try await render(SettingsView(viewModel: settings.settings, initialTab: tab), appearance: .aqua, to: output("settings-\(name)"))
    }

    // 設定のカレンダータブの案内。
    let settingsGuides: [(String, Fixture)] = [
        ("settings-calendars-not-determined", Fixture(status: .notDetermined)),
        ("settings-calendars-denied", Fixture(status: .denied)),
        ("settings-calendars-no-calendars", Fixture(accounts: [], calendars: [])),
    ]
    for (name, fixture) in settingsGuides {
        await fixture.settings.load()
        try await render(SettingsView(viewModel: fixture.settings, initialTab: .calendars), appearance: .aqua, to: output(name))
    }
}

NSApplication.shared.setActivationPolicy(.prohibited)

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("使い方: barlunari-snapshots <出力ディレクトリ>\n".utf8))
    exit(2)
}
do {
    try await runSnapshots(outputDirectory: URL(fileURLWithPath: arguments[1], isDirectory: true))
} catch {
    FileHandle.standardError.write(Data("スナップショットの出力に失敗した: \(error)\n".utf8))
    exit(1)
}
