import AppKit
import BarlunariApplication
import BarlunariDomain
import BarlunariPresentation
import BarlunariPreviewSupport
import SwiftUI

// ポップオーバーを、アプリと同じ MenuBarPanel（同じ NSHostingView の設定、同じフレームの決め方）に載せ、合成した NSEvent を sendEvent で直接渡す。
// パネルは alphaValue = 0、デスクトップより背面のレベル、ignoresMouseEvents = true で orderBack する。
// システムのイベントキューには流さないので、利用者のカーソルとフォーカスを奪わない。
// ウィンドウの key 化、アプリの前面化、CGEvent の post は、この型でも呼ばない。

enum DriverError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self {
        case .message(let text): text
        }
    }
}

@MainActor
final class Harness {
    let viewModel: CalendarPopoverViewModel
    /// 開いたシステム設定の画面を記録する。結果の 1 行に出す。
    private let settingsOpener = FakeSystemSettingsOpener()
    /// サーバーにだけある予定を持つ予定リポジトリ。同期を求められたときに、ローカルに取り込む。
    private let eventRepository: SyncableEventRepository
    private let sourceRefresher: FakeCalendarSourceRefresher
    /// スリープからの復帰の通知を流す、注入したワークスペースの通知センター。
    private let workspaceNotificationCenter = NotificationCenter()
    private let panel: MenuBarPanel
    private var hosting: NSView { panel.contentView ?? NSView() }
    /// 月表示の大きさを決める可視領域。実行する機械の画面に依らず、目標の大きさ 1862x1100（3 列）で出す。
    static let visibleFrame = CGRect(x: 0, y: 0, width: 2056, height: 1215)
    /// 直近の Esc で行った動作。
    private(set) var lastEscape: PopoverEscapeAction?

    /// パネルを置く基準。実際の主ディスプレイの中央のメニューバーの下に置く。画面外に置くと、NSScrollView のスクロールが動かない。
    /// 主ディスプレイが月表示の大きさより小さいと、パネルは主ディスプレイの可視領域に収まる大きさに縮む。
    static func anchor() -> PopoverAnchor {
        let screen = NSScreen.main
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let display = DisplayGeometry(frame: frame, visibleFrame: screen?.visibleFrame ?? visibleFrame)
        let click = CGPoint(x: frame.midX, y: frame.maxY - 5)
        let plan = PopoverPlacement.plan(
            click: click, displays: [display], buttonFrame: nil, menuBarThickness: NSStatusBar.system.thickness
        )
        return plan?.anchor ?? PopoverAnchor(clickX: frame.midX, menuBarBottom: frame.maxY - 24, visibleFrame: display.visibleFrame)
    }
    private var eventNumber = 0

    /// 起動時に使う予定とカレンダーのデータ。
    enum DataSet {
        /// `SampleData.monthViewEvents`
        case standard
        /// `SampleData.denseMonthViewEvents`。予定の多い月で性能を測る。
        case dense
        /// `ColorfulSampleData`。明るい色、暗い色、低彩度の色を含む多数のカレンダーで、色の見やすさを確かめる。
        case colorful
    }

    init(dataSet: DataSet = .standard) async {
        let dateProvider = FixedDateProvider()
        let authorizer = FakeCalendarAccessAuthorizer(status: .fullAccess)
        let calendarRepository = InMemoryCalendarRepository(
            accounts: dataSet == .colorful ? ColorfulSampleData.accounts : SampleData.accounts,
            calendars: dataSet == .colorful ? ColorfulSampleData.calendars : SampleData.calendars
        )
        let events: [CalendarEvent] = switch dataSet {
        case .standard: SampleData.monthViewEvents
        case .dense: SampleData.denseMonthViewEvents
        case .colorful: ColorfulSampleData.events
        }
        let eventRepository = SyncableEventRepository(events: events)
        // 実機では、同期が終わると EventKit が変更通知を送る。サーバーの予定を取り込めたときだけ、同じ通知を送る。
        let sourceRefresher = FakeCalendarSourceRefresher {
            if eventRepository.pullRemote() { NotificationCenter.default.post(name: .calendarStoreDidChange, object: nil) }
        }
        self.eventRepository = eventRepository
        self.sourceRefresher = sourceRefresher
        let visibility = InMemoryCalendarVisibilityRepository()
        let displayModeStore = InMemoryDisplayModeStore()
        viewModel = CalendarPopoverViewModel(
            loadAgenda: LoadAgendaUseCase(
                authorizer: authorizer,
                calendarRepository: calendarRepository,
                eventRepository: eventRepository,
                visibilityRepository: visibility,
                dateProvider: dateProvider
            ),
            requestCalendarAccess: RequestCalendarAccessUseCase(authorizer: authorizer),
            openSystemSettings: OpenSystemSettingsUseCase(opener: settingsOpener),
            refreshCalendarSources: RefreshCalendarSourcesUseCase(refresher: sourceRefresher),
            dateProvider: dateProvider,
            urlOpener: FakeURLOpener(),
            changeNotifier: DataChangeNotifier(),
            loadDisplayMode: LoadDisplayModeUseCase(store: displayModeStore),
            saveDisplayMode: SaveDisplayModeUseCase(store: displayModeStore),
            listCalendars: ListCalendarsUseCase(
                authorizer: authorizer, calendarRepository: calendarRepository, visibilityRepository: visibility
            ),
            setCalendarVisibility: SetCalendarVisibilityUseCase(visibilityRepository: visibility),
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        let root = CalendarPopoverView(viewModel: viewModel, openSettings: {}, quit: {}, visibleFrame: Self.visibleFrame)
            .background(Color(nsColor: .windowBackgroundColor))
        panel = MenuBarPanel(rootView: root)
        panel.allowsKey = false
        panel.appearance = NSAppearance(named: .aqua)
        panel.place(at: Self.anchor())
        let model = viewModel
        panel.onEscape = { [weak self] in
            // アプリの MenuBarController と同じ処理。パネルを閉じる動作（.closePanel）は、このツールでは開閉しないので記録だけする。
            self?.lastEscape = model.performEscape()
        }

        NSApplication.shared.finishLaunching()
        // 画面外に置くと、NSScrollView がスクロールを反映しない。ディスプレイの範囲内に置きつつ、利用者の目にも
        // 操作にも触れないよう、完全に透明にし、デスクトップより背面に置き、マウスを通す。orderBack は key にもしない。
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        panel.collectionBehavior = [.stationary, .ignoresCycle, .transient]
        showPanel()
        viewModel.reload()
        await viewModel.waitForLoad()
        await settle()
    }

    // MARK: 同期

    /// サーバーにだけある予定を 1 件用意する。選択日の 14 時から 1 時間。次に同期を求められるまで、ローカルには届かない。
    func addRemoteEvent(title: String) {
        eventRepository.stageRemote(SampleData.workEvent(title, on: viewModel.selectedDay, hour: 14))
    }

    /// `.calendarStoreDidChange` を `count` 回続けて送る。
    func postStoreChanges(count: Int) {
        for _ in 0..<count { NotificationCenter.default.post(name: .calendarStoreDidChange, object: nil) }
    }

    /// スリープからの復帰の通知を、注入したワークスペースの通知センターに送る。
    func postWake() {
        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: 表示

    /// パネルを隠す。アプリの `MenuBarController.close` と同じく `orderOut` を呼ぶ。
    /// パネルの外観を切り替える。ライトとダークで、パレットの色の役割が切り替わることを確かめる。
    func setAppearance(dark: Bool) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        panel.appearance = appearance
        NSApplication.shared.appearance = appearance
    }

    func hidePanel() {
        panel.orderOut(nil)
    }

    /// パネルを出し直す。アプリの `MenuBarController.open` は同じインスタンスを `orderFrontRegardless` で出すが、
    /// このツールでは key にも前面にもしないよう、完全に透明な背面のまま `orderBack` で出す。
    func showPanel() {
        panel.orderBack(nil)
    }

    /// パネルを出し直し、開いたときの処理を行う。アプリでは、パネルが key になったことが `popoverDidAppear()` を呼ぶ。
    /// このツールのパネルは key にならないので、ここで呼ぶ。
    func reopenPanel() {
        showPanel()
        viewModel.popoverDidAppear()
    }

    /// 内容の大きさにパネルを合わせる。アプリでは次のランループに予約されるフレームの書き直しを、操作のたびに今すぐ行う。
    private func fit() {
        hosting.layoutSubtreeIfNeeded()
        panel.updateFrame()
        hosting.layoutSubtreeIfNeeded()
    }

    /// 指定の時間、ランループを回す。操作ツールの処理はメインアクターの 1 つのジョブの中で動くので、ランループを回すだけでは、
    /// アプリのメインアクターの Task（予定の読み込み、`Task.sleep` のあとの処理）が、操作が終わるまで動かない。
    /// 実際のアプリと同じ順に進めるため、短く回しては `Task.yield()` で、待っているメインアクターのジョブに順番を譲る。
    private func pump(_ seconds: TimeInterval) async {
        let deadline = Date(timeIntervalSinceNow: seconds)
        repeat {
            Self.runLoop(until: min(deadline, Date(timeIntervalSinceNow: 0.001)))
            await Task.yield()
        } while Date() < deadline
    }

    private static func runLoop(until date: Date) {
        RunLoop.current.run(until: date)
    }

    private func capture() -> (png: Data, pixelWidth: Int, pixelHeight: Int)? {
        fit()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return (data, rep.pixelsWide, rep.pixelsHigh)
    }

    /// 表示が落ち着くまで待つ。アニメーションの長さ以上は待ち、連続する 2 回の描画が一致したら落ち着いたとみなす。
    func settle() async {
        await pump(0.35)
        var previous: Data?
        for _ in 0..<30 {
            await Task.yield()
            await pump(0.08)
            guard let current = capture()?.png else { continue }
            if current == previous { return }
            previous = current
        }
    }

    func wait(milliseconds: Int) async {
        await pump(Double(milliseconds) / 1000)
    }

    struct Shot {
        let url: URL
        let pixelWidth: Int
        let pixelHeight: Int
        let pointWidth: Double
        let pointHeight: Double
        var scale: Double { pointWidth > 0 ? Double(pixelWidth) / pointWidth : 0 }
    }

    func screenshot(to url: URL) throws -> Shot {
        guard let image = capture() else { throw DriverError.message("PNG を作れなかった") }
        try image.png.write(to: url)
        return Shot(
            url: url, pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight,
            pointWidth: hosting.bounds.width, pointHeight: hosting.bounds.height
        )
    }

    /// パネルのフレーム（画面座標、左下原点）と上端。表示モードの切り替えや詳細の開閉で、高さは変わるが上端は動かないことを確かめる。
    var panelSummary: String {
        let frame = panel.frame
        func format(_ value: CGFloat) -> String { String(format: "%.0f", value) }
        return "panel=\(format(frame.minX)),\(format(frame.minY)),\(format(frame.width)),\(format(frame.height)) top=\(format(frame.maxY))"
    }

    var stateSummary: String {
        let schedule = viewModel.selectedDaySchedule
        let rows = schedule.allDay.count + schedule.blocks.count
        let detail = viewModel.eventDetail.map { "「\($0.title)」" } ?? "なし"
        let escape = lastEscape.map { " 直近のEsc=\($0)" } ?? ""
        let settings = settingsOpener.openedDestinations.isEmpty ? "" : " システム設定=\(settingsOpener.openedDestinations)"
        let hiddenCount = viewModel.calendarFilterSections.flatMap(\.items).filter { !$0.isVisible }.count
        let filter = "\(viewModel.isCalendarFilterOpen ? "開" : "閉")(\(viewModel.calendarFilterPhase) 非表示=\(hiddenCount)件)"
        return "モード=\(viewModel.displayMode.rawValue) カレンダー一覧=\(filter) 選択日=\(viewModel.selectedDay) 表示月=\(viewModel.displayedMonth) 状態=\(viewModel.phase) 詳細=\(detail) 一覧=\(viewModel.agendaDayCount)日 選択日の件数=\(rows)件(終日\(schedule.allDay.count) 時刻付き\(schedule.blocks.count))\(escape)\(settings) 取得=\(eventRepository.fetchCount)回 同期要求=\(sourceRefresher.refreshCount)回"
    }

    // MARK: イベントの合成

    private var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// View のポイント（左上原点）を、ウィンドウの座標（左下原点）にする。
    private func windowPoint(_ x: Double, _ y: Double) throws -> NSPoint {
        fit()
        let size = hosting.bounds.size
        guard x >= 0, y >= 0, x <= size.width, y <= size.height else {
            throw DriverError.message("座標が範囲外である: (\(x), \(y)) 範囲は \(size.width)x\(size.height)")
        }
        return NSPoint(x: x, y: size.height - y)
    }

    private func makeMouse(_ type: NSEvent.EventType, at point: NSPoint, clickCount: Int = 1, pressure: Float) throws -> NSEvent {
        eventNumber += 1
        guard let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: timestamp,
            windowNumber: panel.windowNumber, context: nil, eventNumber: eventNumber,
            clickCount: clickCount, pressure: pressure
        ) else { throw DriverError.message("マウスイベントを作れなかった") }
        return event
    }

    /// マウスは NSApp.sendEvent から届ける。ローカルモニターも呼ばれ、実際のアプリと同じ経路になる。
    private func deliver(_ event: NSEvent) {
        NSApplication.shared.sendEvent(event)
    }

    /// キーイベントは、windowNumber のウインドウ（このパネル。key にはしない）へ NSApp.sendEvent が渡す。ローカルモニターも呼ばれる。
    /// パネルの sendEvent を重ねて呼ぶと、Esc が 2 回届いてしまう。
    /// パネルは key にしないので、`NSApp.sendEvent` ではキーがパネルに届かない。⌘ 付きのキーはキーボードショートカットとして処理し、
    /// 処理されなかったキーはパネルに直接届ける。1 つのキーは 1 回だけ届ける。
    private func deliverKey(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.contains(.command), panel.performKeyEquivalent(with: event) { return }
        panel.sendEvent(event)
    }

    /// スクロールは CGEvent 由来で、スクロールの CGEvent は windowNumber のフィールドを保持しないため、event.window が nil になる。
    /// window を差し替えたプロキシを NSApp.sendEvent に渡し、ローカルモニターとウィンドウの両方に届ける。
    private func deliverScroll(_ base: NSEvent) {
        let event = base.window == nil ? ScrollEventProxy.make(base: base, window: panel, location: base.locationInWindow) : base
        NSApplication.shared.sendEvent(event)
    }

    func hover(x: Double, y: Double) throws {
        let point = try windowPoint(x, y)
        deliver(try makeMouse(.mouseMoved, at: point, clickCount: 0, pressure: 0))
    }

    /// 押した位置のビューか、その親に NSControl があるか。
    private func hitsControl(at point: NSPoint) -> Bool {
        var view = panel.contentView?.superview?.hitTest(point)
        while let current = view {
            if current is NSControl { return true }
            view = current.superview
        }
        return false
    }

    /// 不変条件: SwiftUI のジェスチャー（onTapGesture）には、mouseDown と mouseUp をどちらもその場で `deliver` する。
    /// mouseUp を先にアプリのキューへ積む経路は、1 回目の押下だけ SwiftUI に届き、2 回目以降は届かない。キューに積むのは NSControl の追跡ループがある押下だけにする。
    func click(x: Double, y: Double) throws {
        let point = try windowPoint(x, y)
        deliver(try makeMouse(.mouseMoved, at: point, clickCount: 0, pressure: 0))
        let down = try makeMouse(.leftMouseDown, at: point, pressure: 1)
        let up = try makeMouse(.leftMouseUp, at: point, pressure: 0)
        if hitsControl(at: point) {
            // AppKit のボタンは mouseDown の中で、mouseUp が届くまでイベントの追跡ループを回す。
            // アプリ自身のイベントキューに mouseUp を積んでおくと、ループがそれを取り出して抜ける。システムのキューには流さない。
            NSApplication.shared.postEvent(up, atStart: false)
            deliver(down)
            while let rest = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) {
                deliver(rest)
            }
        } else {
            deliver(down)
            deliver(up)
        }
    }

    func pressEscape() async throws {
        try await pressKey(characters: "\u{1b}", keyCode: 53, modifiers: [])
    }

    /// ⌘ と数字のキー。表示モードの切り替えのショートカットを確かめるために使う。
    func pressCommand(digit: Int) async throws {
        let codes = [1: 18, 2: 19]
        guard let code = codes[digit] else { throw DriverError.message("使えるのは cmd+1 と cmd+2 だけである") }
        try await pressKey(characters: String(digit), keyCode: UInt16(code), modifiers: .command)
    }

    private func pressKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) async throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: timestamp,
                windowNumber: panel.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ) else { throw DriverError.message("キーイベントを作れなかった") }
            deliverKey(event)
            await pump(0.02)
        }
    }

    enum ScrollKind: String { case trackpad, wheel, fling, drag }

    /// `fling` の 1 フレームの間隔。120Hz のディスプレイの 1 フレーム。
    static let flingFrameInterval: TimeInterval = 1.0 / 120
    /// `fling` の慣性で、1 フレームごとに変化量に掛ける率。
    private static let flingDecay = 0.94
    /// `fling` の指が触れている間のイベントの数。
    private static let flingTouchEvents = 8

    /// 直前の `fling` の、フレームごとの CPU 時間（ミリ秒）と経過時間（ミリ秒）。
    private(set) var lastFrames: [(cpu: Double, wall: Double, instructions: Double)] = []

    /// CGEvent のスクロールを作って NSEvent に変換する。CGEvent は post しない。
    /// CGEvent の位置には、ウィンドウ内の座標（左下原点）を主ディスプレイの高さで上下反転して入れる。
    /// NSEvent の locationInWindow がウィンドウ内の座標になる。実際の画面の位置とは対応させない。
    private func scrollEvent(
        point: NSPoint, dy: Double, continuous: Bool, phase: Int64, momentum: Int64
    ) throws -> NSEvent {
        guard let cg = CGEvent(
            scrollWheelEvent2Source: nil, units: continuous ? .pixel : .line, wheelCount: 1,
            wheel1: Int32(dy.rounded()), wheel2: 0, wheel3: 0
        ) else { throw DriverError.message("CGEvent を作れなかった") }
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        cg.location = CGPoint(x: point.x, y: screenHeight - point.y)
        // ウィンドウの番号を指定しても、スクロールの CGEvent は保持せず、NSEvent の window は nil になる。deliverScroll で補う。
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(panel.windowNumber))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(panel.windowNumber))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        if continuous {
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        }
        guard let event = NSEvent(cgEvent: cg) else { throw DriverError.message("NSEvent に変換できなかった") }
        return event
    }

    /// `dy` の符号は `NSEvent.scrollingDeltaY` と同じ。正で内容が下へ動き、一覧は先頭側へ戻る。
    func scroll(x: Double, y: Double, dy: Double, kind: ScrollKind) async throws {
        let point = try windowPoint(x, y)
        switch kind {
        case .wheel:
            deliverScroll(try scrollEvent(point: point, dy: dy, continuous: false, phase: 0, momentum: 0))
        case .trackpad:
            // CGScrollPhase: began=1, changed=2, ended=4。CGMomentumScrollPhase: begin=1, continue=2, end=3。
            let steps = 6
            let step = dy / Double(steps)
            deliverScroll(try scrollEvent(point: point, dy: step, continuous: true, phase: 1, momentum: 0))
            await pump(0.016)
            for _ in 1..<steps - 1 {
                deliverScroll(try scrollEvent(point: point, dy: step, continuous: true, phase: 2, momentum: 0))
                await pump(0.016)
            }
            deliverScroll(try scrollEvent(point: point, dy: step, continuous: true, phase: 2, momentum: 0))
            await pump(0.016)
            deliverScroll(try scrollEvent(point: point, dy: 0, continuous: true, phase: 4, momentum: 0))
            await pump(0.016)
            var momentumDelta = step * 0.6
            for index in 0..<4 {
                deliverScroll(try scrollEvent(
                    point: point, dy: momentumDelta, continuous: true, phase: 0, momentum: index == 0 ? 1 : 2
                ))
                momentumDelta *= 0.6
                await pump(0.016)
            }
            deliverScroll(try scrollEvent(point: point, dy: 0, continuous: true, phase: 0, momentum: 3))
        case .fling:
            try await fling(at: point, dy: dy, momentumAsTouch: false)
        case .drag:
            try await fling(at: point, dy: dy, momentumAsTouch: true)
        }
    }

    /// 実際のトラックパッドに近い、細かいイベントのスクロール。指が触れている間は同じ変化量を 1 フレームごとに送り、
    /// 指を離したあとは慣性の変化量を 1 フレームごとに減らしながら、0.5pt を下回るまで送る。合計の移動量はおよそ `dy` になる。
    /// フレームごとに、イベントを渡してから次のフレームまでの CPU 時間と経過時間を記録する。
    ///
    /// 合成した慣性のイベントは `NSScrollView` に反映されないので、`momentumAsTouch` が `true` のとき（`drag`）は、
    /// 慣性と同じ変化量の並びを、指が触れたままのイベントとして送る。慣性で流れる区間と同じ距離と速度で、フレームごとの重さを測るために使う。
    private func fling(at point: NSPoint, dy: Double, momentumAsTouch: Bool) async throws {
        // 指の間の合計 n×g と慣性の合計 g/(1-r) を足して dy にする。
        let delta = dy / (Double(Self.flingTouchEvents) + 1 / (1 - Self.flingDecay))
        var steps: [(dy: Double, phase: Int64, momentum: Int64)] = []
        for index in 0..<Self.flingTouchEvents {
            steps.append((delta, index == 0 ? 1 : 2, 0))
        }
        if !momentumAsTouch { steps.append((0, 4, 0)) }
        var momentum = delta
        var isFirst = true
        while abs(momentum) >= 0.5 {
            steps.append(momentumAsTouch ? (momentum, 2, 0) : (momentum, 0, isFirst ? 1 : 2))
            momentum *= Self.flingDecay
            isFirst = false
        }
        steps.append(momentumAsTouch ? (0, 4, 0) : (0, 0, 3))

        lastFrames = []
        for step in steps {
            // 速度はイベントのタイムスタンプから求められるので、送る直前に作る。
            let event = try scrollEvent(point: point, dy: step.dy, continuous: true, phase: step.phase, momentum: step.momentum)
            let cpuStart = processCPUMilliseconds()
            let wallStart = ProcessInfo.processInfo.systemUptime
            let instructionsStart = processInstructionsMillions()
            deliverScroll(event)
            await pump(Self.flingFrameInterval)
            lastFrames.append((
                processCPUMilliseconds() - cpuStart,
                (ProcessInfo.processInfo.systemUptime - wallStart) * 1000,
                processInstructionsMillions() - instructionsStart
            ))
        }
    }
}
