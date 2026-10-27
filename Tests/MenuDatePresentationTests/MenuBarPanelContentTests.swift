import AppKit
import MenuDateApplication
import SwiftUI
import Testing
@testable import MenuDatePresentation

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

/// 本物の `CalendarPopoverView` をパネルに載せ、画面に出さずに（`orderFront` も `makeKey` も呼ばない）フレームの決まり方を確かめる。
@MainActor
@Suite("MenuBarPanel と CalendarPopoverView")
struct MenuBarPanelContentTests {
    private let area = PopoverScreenArea(visibleFrame: CGRect(x: 0, y: 74, width: 2056, height: 1215))
    private let anchor = PopoverAnchor(
        clickX: 1000, menuBarBottom: 1289, visibleFrame: CGRect(x: 0, y: 74, width: 2056, height: 1215)
    )

    private func makePanel(_ harness: Harness) -> MenuBarPanel {
        MenuBarPanel(rootView: CalendarPopoverView(viewModel: harness.popover, openSettings: {}, quit: {}, screenArea: area))
    }

    @Test func 月表示のパネルは_渡された領域から決まる大きさで出る() async {
        let harness = Harness(displayMode: .month)
        let panel = makePanel(harness)
        panel.place(at: anchor)
        #expect(panel.frame.size == MonthPopoverSizing.targetSize)
        #expect(panel.frame.maxY == 1289 - PopoverPlacement.gap)
        #expect(abs(panel.frame.midX - 1000) <= 0.5)
    }

    @Test func 領域が小さいディスプレイに移ると_月表示のパネルは縮み_上端は動かない() async {
        let harness = Harness(displayMode: .month)
        let panel = makePanel(harness)
        panel.place(at: anchor)
        let top = panel.frame.maxY

        // 高さ 600 の領域。余白 24pt ずつを引いた 552pt になる。
        area.update(CGRect(x: 0, y: 74, width: 2056, height: 600))
        await pump(0.3)
        #expect(panel.frame.size == CGSize(width: 1862, height: 552))
        #expect(panel.frame.maxY == top)
    }

    @Test func 表示モードを切り替えると_パネルは内容に合わせて変わり_上端は動かない() async {
        let harness = Harness(displayMode: .month)
        let panel = makePanel(harness)
        panel.place(at: anchor)
        let top = panel.frame.maxY

        harness.popover.setDisplayMode(.compact)
        await pump(0.3)
        #expect(panel.frame.width == CalendarPopoverView.width)
        #expect(panel.frame.height < MonthPopoverSizing.targetSize.height)
        #expect(panel.frame.maxY == top)

        harness.popover.setDisplayMode(.month)
        await pump(0.3)
        #expect(panel.frame.size == MonthPopoverSizing.targetSize)
        #expect(panel.frame.maxY == top)
    }

    @Test func コンパクト表示で詳細を開閉すると_パネルの高さが変わり_上端は動かない() async {
        let harness = Harness(displayMode: .compact)
        let viewModel = await harness.loadedPopover()
        let panel = makePanel(harness)
        panel.place(at: anchor)
        await pump(0.3)
        let listHeight = panel.frame.height
        let top = panel.frame.maxY

        let row = viewModel.selectedSection.rows.first
        guard let row else {
            Issue.record("選択日に予定がない")
            return
        }
        viewModel.showDetail(of: row)
        await pump(0.6)
        let detailHeight = panel.frame.height
        #expect(detailHeight != listHeight)
        #expect(panel.frame.maxY == top)

        viewModel.closeDetail()
        await pump(0.6)
        #expect(panel.frame.height == listHeight)
        #expect(panel.frame.maxY == top)
    }

    @Test func パネルが_keyになった通知で_開いたときの処理が動く() async {
        let harness = Harness(displayMode: .compact)
        let viewModel = await harness.loadedPopover()
        let panel = makePanel(harness)
        panel.place(at: anchor)
        await pump(0.1)
        guard let row = viewModel.selectedSection.rows.first else {
            Issue.record("選択日に予定がない")
            return
        }
        viewModel.showDetail(of: row)
        #expect(viewModel.eventDetail != nil)

        // パネルを実際に key にはしない。key になったときの通知だけを流す。
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: panel)
        await waitUntil { viewModel.eventDetail == nil }
        #expect(viewModel.eventDetail == nil)
    }
}
