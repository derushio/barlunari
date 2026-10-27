import AppKit
import Testing

@testable import BarlunariPresentation

/// 最初のスクロールの前にディスプレイリンクを作る先の用意。ウインドウは画面に出さない（作るだけで、前面化もしない）。
@MainActor
@Suite struct CanvasWarmupTests {
    private static func makeWindow() -> NSWindow {
        NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
    }

    @Test func ウインドウに取り付けたあとの先の用意は何度呼んでも落ちない() {
        let warmup = CanvasWarmup()
        let window = Self.makeWindow()
        warmup.attach(to: window)
        warmup.warmDisplayLink()
        warmup.warmDisplayLink()
        #expect(window.isVisible == false)
    }

    @Test func ウインドウがなければ先の用意は何もしない() {
        let warmup = CanvasWarmup()
        warmup.warmDisplayLink()
        warmup.attach(to: nil)
        warmup.warmDisplayLink()
    }

    @Test func 取り付けたウインドウが解放されたあとも先の用意は落ちない() {
        let warmup = CanvasWarmup()
        var window: NSWindow? = Self.makeWindow()
        warmup.attach(to: window)
        window = nil
        warmup.warmDisplayLink()
        #expect(window == nil)
    }
}
