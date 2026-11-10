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
        self.panel = panel
    }

    /// 自己確認の通知の名前。`enableSelfCheck()` のあと、この通知を受けるたびにアイコンの押下と同じ処理を行う。
    public static let selfCheckToggleNotification = Notification.Name("io.github.derushio.Barlunari.selfCheckToggle")
    private var selfCheckObserver: (any NSObjectProtocol)?

    /// 実機の開閉の処理を、利用者の画面とフォーカスを変えずに確かめるためのモード。`install()` のあとに呼ぶ。
    ///
    /// パネルを完全に透明にし、マウスを通し、key にしない。`selfCheckToggleNotification` の分散通知を受けるたびに、
    /// アイコンの押下と同じ処理を行う。結果は panel カテゴリのログで確かめる。アプリは、起動時の環境変数
    /// `BARLUNARI_PANEL_SELF_CHECK=1` があるときだけ、このモードにする。
    public func enableSelfCheck() {
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
            let size = NSFont.menuBarFont(ofSize: 0).pointSize
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(
                string: text,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)]
            )
            button.setAccessibilityLabel(countdown.accessibilityLabel ?? MenuBarIcon.accessibilityLabel)
        } else {
            button.attributedTitle = NSAttributedString(string: "")
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
        guard let panel else { return }
        let displays = NSScreen.screens.map { DisplayGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        guard let plan = PopoverPlacement.plan(
            click: NSEvent.mouseLocation,
            displays: displays,
            buttonFrame: statusItem?.button?.window?.frame,
            menuBarThickness: NSStatusBar.system.thickness
        ) else { return }
        // 出す前に、出すディスプレイの領域を渡して大きさを決める。
        screenArea.update(plan.visibleArea)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.place(at: plan.anchor)
        isShown = true
        let wasHidden = NSApp.isHidden
        panel.unhideApplicationIfNeeded()
        panel.orderFrontRegardless()
        panel.makeKey()
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
    }

    /// パネルを閉じる。閉じていれば何もしない。
    func close(_ reason: PopoverCloseReason) {
        guard isShown else { return }
        panelLog.notice("close reason=\(String(describing: reason), privacy: .public)")
        isShown = false
        gate.recordClose(reason, at: Date())
        removeMonitors()
        panel?.orderOut(nil)
    }

    private func panelDidResignKey() {
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
            MainActor.assumeIsolated { self?.close(.otherApp) }
        }
        let center = NSWorkspace.shared.notificationCenter
        let ownIdentifier = Bundle.main.bundleIdentifier
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let isOther = app?.bundleIdentifier != ownIdentifier
                if isOther { MainActor.assumeIsolated { self?.close(.otherApp) } }
            },
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(.otherApp) }
            },
        ]
    }

    private func removeMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        globalMouseMonitor = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers = []
    }
}
