import AppKit
import SwiftUI

/// 設定のウインドウ。`NSWindow` に `SettingsView` を載せ、同じウインドウを使い回す。大きさと位置は保存する。
@MainActor
public final class SettingsWindowController {
    /// 大きさと位置の保存名。
    static let frameAutosaveName = "BarlunariSettings"

    private let viewModel: SettingsViewModel
    private var window: NSWindow?

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    /// 設定を開く。利用者が押したときだけ呼ばれるので、アプリを前面にしてフォーカスを得る。
    public func show() {
        let window = window ?? makeWindow()
        self.window = window
        // LSUIElement のアプリは前面にならないため、先にアクティブにしないとウインドウが背面に開く。
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(viewModel: viewModel))
        let window = NSWindow(contentViewController: controller)
        window.title = "Barlunari の設定"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        // 保存された大きさと位置があれば、ここで復元される。
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return window
    }
}
