import AppKit
import OSLog
import SwiftUI

/// パネルの開閉のログ。予定の内容は出さない。
private let panelLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Barlunari", category: "panel")

/// メニューバーの項目（`NSStatusItem`）とパネルを管理する。クリックでパネルを開閉する。
///
/// 開き方: クリックの位置があるディスプレイを `PopoverPlacement` で決め、そのディスプレイの領域を `PopoverScreenArea` に渡し、
/// パネルの大きさと位置を決めてから前に出す。アプリは前面にしない。
///
/// 閉じ方（`PopoverCloseReason`）: アイコンをもう一度押す、パネルが key でなくなる、別のアプリが前面になる・他のアプリのクリック・デスクトップの切り替え、
/// Esc（詳細や日の予定の一覧が開いていればそれを先に閉じる）、設定を開く。
@MainActor
public final class MenuBarController: NSObject {
    private let viewModel: CalendarPopoverViewModel
    private let countdown: MenuBarCountdownViewModel
    private let openSettingsAction: @MainActor () -> Void
    private let quitAction: @MainActor () -> Void
    private let screenArea = PopoverScreenArea(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    private var gate = PopoverToggleGate()
    private var isShown = false
    private var globalMouseMonitor: Any?
    private var workspaceObservers: [any NSObjectProtocol] = []
    /// 開いたあとに、パネルが今の操作スペースから外れていないかを確かめる処理。確かめ終えるか閉じるまで nil にしない。
    private var spaceCheckTask: Task<Void, Never>?
    private var isSelfCheck = false
    private var simulatedSpaceChecks: [Bool] = []

    public init(
        viewModel: CalendarPopoverViewModel,
        countdown: MenuBarCountdownViewModel,
        openSettings: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.countdown = countdown
        self.openSettingsAction = openSettings
        self.quitAction = quit
        super.init()
    }

    /// メニューバーに項目を出し、パネルを組み立て、次の予定までの残り時間の表示を始める。
    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked)
        }
        statusItem = item
        updateStatusItemButton()
        observeCountdown()
        countdown.start()
        panel = makePanel()
    }

    private func makePanel() -> MenuBarPanel {
        let root = CalendarPopoverView(
            viewModel: viewModel,
            openSettings: { [weak self] in
                self?.close(.openSettings)
                self?.openSettingsAction()
            },
            quit: quitAction,
            screenArea: screenArea
        )
        let panel = MenuBarPanel(rootView: root)
        panel.onResignKey = { [weak self] in self?.panelDidResignKey() }
        panel.onEscape = { [weak self] in self?.handleEscape() }
        if isSelfCheck {
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.allowsKey = false
        }
        return panel
    }

    /// パネルを新しいウインドウに作り直す。
    ///
    /// フルスクリーンの操作スペースの上で key にしたパネルは、`.canJoinAllSpaces` でも 1 つの操作スペースにしか属さなくなり、
    /// 出し直しても今の操作スペースに出なくなることがある。collectionBehavior を設定し直しても戻らず、新しいウインドウなら戻る
    /// （https://github.com/orkunisitmak/clipboardline/pull/255、https://github.com/MHusted01/shortcutlens/pull/160）。
    private func replacePanel(reason: String) -> MenuBarPanel {
        panelLog.notice("panel replaced: \(reason, privacy: .public)")
        panel?.onResignKey = nil
        panel?.onEscape = nil
        panel?.orderOut(nil)
        let fresh = makePanel()
        panel = fresh
        return fresh
    }

    /// 自己確認の通知の名前。`enableSelfCheck()` のあと、この通知を受けるたびにアイコンの押下と同じ処理を行う。
    public static let selfCheckToggleNotification = Notification.Name("io.github.derushio.Barlunari.selfCheckToggle")
    private var selfCheckObserver: (any NSObjectProtocol)?

    /// 実機の開閉の処理を、利用者の画面とフォーカスを変えずに確かめるためのモード。`install()` のあとに呼ぶ。
    ///
    /// パネルを完全に透明にし、マウスを通し、key にしない。`selfCheckToggleNotification` の分散通知を受けるたびに、
    /// アイコンの押下と同じ処理を行う。結果は panel カテゴリのログで確かめる。アプリは、起動時の環境変数
    /// `BARLUNARI_PANEL_SELF_CHECK=1` があるときだけ、このモードにする。
    ///
    /// - Parameter simulatedSpaceChecks: 開いたあとにパネルが今の操作スペースにあるかを確かめるたびに、実際の値の代わりに先頭から
    ///   1 つずつ使う値。フルスクリーンの操作スペースから外れたときの立て直しを、key にしないまま確かめるために使う。
    ///   尽きたら実際の値を使う。このモードでは、立て直しでアプリを前面にしない。
    public func enableSelfCheck(simulatedSpaceChecks: [Bool] = []) {
        isSelfCheck = true
        self.simulatedSpaceChecks = simulatedSpaceChecks
        guard let panel else { return }
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.allowsKey = false
        selfCheckObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.selfCheckToggleNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItemClicked(nil) }
        }
        panelLog.notice("selfCheck enabled")
    }

    // MARK: 残り時間の表示

    /// 残り時間の文字列があれば、アイコンを外して等幅数字のフォントでその文字列を出す。なければアイコンだけに戻す。
    private func updateStatusItemButton() {
        guard let button = statusItem?.button else { return }
        if let text = countdown.displayText {
            button.image = nil
            button.imagePosition = .noImage
            // 文字色は、メニューバーの外観に合わせてボタンが決める。
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
            button.title = text
            button.setAccessibilityLabel(countdown.accessibilityLabel ?? MenuBarIcon.accessibilityLabel)
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: MenuBarIcon.symbolName, accessibilityDescription: MenuBarIcon.accessibilityLabel)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(MenuBarIcon.accessibilityLabel)
        }
    }

    /// 残り時間の表示が変わるたびにボタンを更新する。観測は 1 回ごとに登録し直す。
    private func observeCountdown() {
        withObservationTracking {
            _ = countdown.displayText
            _ = countdown.accessibilityLabel
        } onChange: { [weak self] in
            // onChange は変更の直前に呼ばれる。メインアクターに移ってから読むと、新しい値になっている。
            Task { @MainActor [weak self] in
                self?.updateStatusItemButton()
                self?.observeCountdown()
            }
        }
    }

    // MARK: 開閉

    @objc private func statusItemClicked(_ sender: Any?) {
        panelLog.notice("statusItem isShown=\(self.isShown) mouse=\(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public)")
        if gate.shouldOpen(isShown: isShown, at: Date()) {
            open()
        } else if isShown {
            close(.statusItem)
        }
    }

    private func open() {
        guard var panel else { return }
        let displays = NSScreen.screens.map { DisplayGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        guard let plan = PopoverPlacement.plan(
            click: NSEvent.mouseLocation,
            displays: displays,
            buttonFrame: statusItem?.button?.window?.frame,
            menuBarThickness: NSStatusBar.system.thickness
        ) else { return }
        screenArea.update(plan.visibleArea)
        isShown = true
        let wasHidden = NSApp.isHidden
        panel.unhideApplicationIfNeeded()
        show(panel, at: plan.anchor)
        if !isOnActiveSpace(panel) {
            // 前に開いたときに外れたままのパネルは、出しても今の操作スペースに出ない。
            panel = replacePanel(reason: "not on the active Space after show")
            show(panel, at: plan.anchor)
        }
        installMonitors()
        panelLog.notice(
            "open frame=\(NSStringFromRect(panel.frame), privacy: .public) wasHidden=\(wasHidden) key=\(panel.isKeyWindow) active=\(NSApp.isActive) onActiveSpace=\(panel.isOnActiveSpace)"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak panel] in
            MainActor.assumeIsolated {
                guard let panel else { return }
                panelLog.notice(
                    "open+0.3s visible=\(panel.isVisible) occluded=\(!panel.occlusionState.contains(.visible)) key=\(panel.isKeyWindow) onActiveSpace=\(panel.isOnActiveSpace)"
                )
            }
        }
        scheduleSpaceCheck(anchor: plan.anchor)
    }

    private func show(_ panel: MenuBarPanel, at anchor: PopoverAnchor) {
        // 出す前に、出すディスプレイの領域に合わせた大きさを決める。
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.place(at: anchor)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    /// パネルが今の操作スペースにあるか。自己確認モードで値が指定されていれば、それを先頭から使う。
    private func isOnActiveSpace(_ panel: MenuBarPanel) -> Bool {
        if !simulatedSpaceChecks.isEmpty { return simulatedSpaceChecks.removeFirst() }
        return panel.isOnActiveSpace
    }

    /// パネルがフルスクリーンの操作スペースから外れるまでの時間（約 0.3 秒）より少し長く待つ。
    private static let spaceCheckDelay: Duration = .milliseconds(450)

    /// 開いてから `spaceCheckDelay` ごとに、パネルが今の操作スペースにあるかを確かめ、外れていたら立て直す。
    ///
    /// フルスクリーンの操作スペースの上では、key になったパネルが約 0.3 秒後にその操作スペースから外れ、利用者には何も見えなくなる。
    /// 操作スペースは切り替わらないので、通知では分からない。1 回目は、アプリを前面にして同じパネルを出し直す
    /// （https://github.com/xiufengsun/TokenTracker/issues/681 と同じ対応）。2 回目は、パネルを作り直して出す。
    /// それでも外れていれば、次の押下で開き直せるよう閉じる。
    private func scheduleSpaceCheck(anchor: PopoverAnchor) {
        spaceCheckTask?.cancel()
        spaceCheckTask = Task { [weak self] in
            for attempt in 1...3 {
                try? await Task.sleep(for: Self.spaceCheckDelay)
                guard !Task.isCancelled, let self, self.isShown, var panel = self.panel else { return }
                guard !self.isOnActiveSpace(panel) else { break }
                switch attempt {
                case 1:
                    if self.isSelfCheck {
                        // 自己確認モードでは、利用者のフォーカスを変えないよう、アプリを前面にしない。
                        panelLog.notice("activation skipped in self-check")
                    } else {
                        NSApp.activate()
                    }
                case 2:
                    panel = self.replacePanel(reason: "left the active Space after activation")
                default:
                    panelLog.notice("panel stayed off the active Space")
                    self.spaceCheckTask = nil
                    self.close(.otherApp, trigger: "leftSpace")
                    return
                }
                self.show(panel, at: anchor)
                panelLog.notice("reshow attempt=\(attempt) key=\(panel.isKeyWindow) onActiveSpace=\(panel.isOnActiveSpace)")
            }
            guard !Task.isCancelled else { return }
            self?.spaceCheckTask = nil
        }
    }

    /// 開いたあとの確かめの途中で、パネルが今の操作スペースから外れているか。
    ///
    /// 外れたパネルは key でなくなり、元の前面のアプリが前面に戻る。これで閉じると立て直す前に閉じ、閉じた直後の押下は
    /// `PopoverToggleGate` が閉じる操作として扱うので、押し直しても開かない。この間は閉じずに、立て直しの処理に任せる。
    private var isRecoveringFromLeftSpace: Bool {
        guard spaceCheckTask != nil, let panel else { return false }
        return !panel.isOnActiveSpace
    }

    /// パネルを閉じる。閉じていれば何もしない。
    ///
    /// - Parameter trigger: ログに出す、閉じた契機の詳細。
    func close(_ reason: PopoverCloseReason, trigger: String? = nil) {
        guard isShown else { return }
        panelLog.notice("close reason=\(String(describing: reason), privacy: .public) trigger=\(trigger ?? "-", privacy: .public)")
        isShown = false
        spaceCheckTask?.cancel()
        spaceCheckTask = nil
        gate.recordClose(reason, at: Date())
        removeMonitors()
        panel?.orderOut(nil)
    }

    private func panelDidResignKey() {
        if isRecoveringFromLeftSpace {
            panelLog.notice("close deferred: resignKey while off the active Space")
            return
        }
        close(.focusLoss)
    }

    private func handleEscape() {
        if viewModel.performEscape() == .closePanel { close(.escape) }
    }

    // MARK: 他のアプリの操作

    /// パネルを出している間だけ、他のアプリのクリック、別のアプリの前面化、デスクトップの切り替えを見る。
    private func installMonitors() {
        removeMonitors()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(.otherApp, trigger: "click") }
        }
        let center = NSWorkspace.shared.notificationCenter
        let ownIdentifier = Bundle.main.bundleIdentifier
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let isOther = app?.bundleIdentifier != ownIdentifier
                if isOther { MainActor.assumeIsolated { self?.closeUnlessRecovering(trigger: "activation") } }
            },
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closeUnlessRecovering(trigger: "spaceChange") }
            },
        ]
    }

    /// 別のアプリの前面化と操作スペースの切り替えで閉じる。パネルが今の操作スペースから外れて立て直している間は閉じない。
    private func closeUnlessRecovering(trigger: String) {
        if isRecoveringFromLeftSpace {
            panelLog.notice("close deferred: \(trigger, privacy: .public) while off the active Space")
            return
        }
        close(.otherApp, trigger: trigger)
    }

    private func removeMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        globalMouseMonitor = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers = []
    }
}
