import AppKit
import Observation
import SwiftUI
import Testing
@testable import BarlunariPresentation

/// 高さを変えられる View。内容の大きさが変わったときの、パネルのフレームの書き直しを確かめる。
@MainActor
@Observable
private final class ContentSize {
    var height: CGFloat
    init(height: CGFloat) { self.height = height }
}

private struct SizedContent: View {
    let size: ContentSize
    var body: some View {
        Color.clear.frame(width: 300, height: size.height)
    }
}

/// 非同期の文脈では `RunLoop` を直接呼べないため、同期の関数に包む。
private func runLoop(until date: Date) {
    RunLoop.current.run(until: date)
}

@MainActor
private func pump(_ seconds: TimeInterval) async {
    let deadline = Date(timeIntervalSinceNow: seconds)
    repeat {
        runLoop(until: min(deadline, Date(timeIntervalSinceNow: 0.001)))
        await Task.yield()
    } while Date() < deadline
}

/// パネルは画面に出さない（`orderFront` も `makeKey` も呼ばない）。フレームは出ていなくても書ける。
@MainActor
@Suite("MenuBarPanel")
struct MenuBarPanelTests {
    private let visible = CGRect(x: 0, y: 74, width: 2056, height: 1215)
    private var anchor: PopoverAnchor { PopoverAnchor(clickX: 1000, menuBarBottom: 1289, visibleFrame: visible) }

    @Test func 位置を渡すと_内容の大きさでフレームが決まる() {
        let size = ContentSize(height: 400)
        let panel = MenuBarPanel(rootView: SizedContent(size: size))
        panel.place(at: anchor)
        #expect(panel.frame == CGRect(x: 850, y: 1285 - 400, width: 300, height: 400))
        #expect(!panel.isVisible)
    }

    @Test func 内容の高さが変わると_次のランループで上端を保ったままフレームが書き直される() async {
        let size = ContentSize(height: 400)
        let panel = MenuBarPanel(rootView: SizedContent(size: size))
        panel.place(at: anchor)
        let top = panel.frame.maxY

        size.height = 650
        await pump(0.3)
        #expect(panel.frame.height == 650)
        #expect(panel.frame.maxY == top)

        size.height = 250
        await pump(0.3)
        #expect(panel.frame.height == 250)
        #expect(panel.frame.maxY == top)
        #expect(panel.frame.midX == 1000)
    }

    @Test func フレームの書き直しは_レイアウトの最中ではなく予約されて1回にまとまる() async {
        let size = ContentSize(height: 400)
        let panel = MenuBarPanel(rootView: SizedContent(size: size))
        panel.place(at: anchor)
        size.height = 500
        panel.scheduleFrameUpdate()
        panel.scheduleFrameUpdate()
        // 予約しただけでは、まだ書き直されない。
        #expect(panel.frame.height == 400)
        await pump(0.3)
        #expect(panel.frame.height == 500)
    }

    @Test func 別のディスプレイの基準に置き直すと_その位置へ移る() {
        let size = ContentSize(height: 400)
        let panel = MenuBarPanel(rootView: SizedContent(size: size))
        panel.place(at: anchor)
        let external = CGRect(x: -378, y: 1329, width: 2560, height: 1440)
        panel.place(at: PopoverAnchor(clickX: 1000, menuBarBottom: 2739, visibleFrame: external))
        #expect(panel.frame == CGRect(x: 850, y: 2735 - 400, width: 300, height: 400))
    }

    @Test func パネルは枠なしで_アプリを前面にせず_keyになれる() {
        let panel = MenuBarPanel(rootView: SizedContent(size: ContentSize(height: 100)))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.hasShadow)
        #expect(!panel.isOpaque)
    }

    @Test func Escは_ウインドウに届く前に_onEscapeへ渡される() throws {
        let panel = MenuBarPanel(rootView: SizedContent(size: ContentSize(height: 100)))
        var count = 0
        panel.onEscape = { count += 1 }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
        panel.sendEvent(event)
        #expect(count == 1)
    }

    @Test func 修飾キー付きのEscは_onEscapeへ渡さない() throws {
        let panel = MenuBarPanel(rootView: SizedContent(size: ContentSize(height: 100)))
        var count = 0
        panel.onEscape = { count += 1 }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
        panel.sendEvent(event)
        #expect(count == 0)
    }
}
