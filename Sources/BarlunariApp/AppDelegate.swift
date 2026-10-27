import AppKit
import BarlunariPresentation

/// 起動時に、依存の組み立て（`AppContainer`）、メニューバーの項目とパネル、設定のウインドウを作る。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: AppContainer?
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let container = AppContainer()
        let settings = SettingsWindowController(viewModel: container.settingsViewModel)
        let menuBar = MenuBarController(
            viewModel: container.popoverViewModel,
            openSettings: { settings.show() },
            quit: { NSApp.terminate(nil) }
        )
        menuBar.install()
        if ProcessInfo.processInfo.environment["BARLUNARI_PANEL_SELF_CHECK"] == "1" { menuBar.enableSelfCheck() }
        NSApp.mainMenu = MainMenu.make()
        self.container = container
        settingsWindowController = settings
        menuBarController = menuBar
    }

    /// ウインドウをすべて閉じても終了しない。メニューバーに常駐する。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
