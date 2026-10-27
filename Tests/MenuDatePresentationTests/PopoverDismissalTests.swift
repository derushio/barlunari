import Foundation
import Testing
@testable import MenuDatePresentation

@Suite("PopoverDismissal")
struct PopoverDismissalTests {
    @Test(arguments: [
        (true, true, PopoverEscapeAction.closeDetail),
        (true, false, .closeDetail),
        (false, true, .closeCalendarFilter),
        (false, false, .closePanel),
    ])
    func Escで閉じるものを決める(hasDetail: Bool, hasCalendarFilter: Bool, expected: PopoverEscapeAction) {
        #expect(PopoverEscapeAction.resolve(hasDetail: hasDetail, hasCalendarFilter: hasCalendarFilter) == expected)
    }

    @Test func 表示中のアイコンの押下は閉じる操作になる() {
        let gate = PopoverToggleGate()
        #expect(!gate.shouldOpen(isShown: true, at: Date()))
    }

    @Test func 閉じているときのアイコンの押下は開く操作になる() {
        let gate = PopoverToggleGate()
        #expect(gate.shouldOpen(isShown: false, at: Date()))
    }

    @Test(arguments: [PopoverCloseReason.focusLoss, .otherApp])
    func アイコンの押下で先に閉じた直後の押下は_開き直さない(reason: PopoverCloseReason) {
        var gate = PopoverToggleGate()
        let closedAt = Date(timeIntervalSince1970: 1000)
        gate.recordClose(reason, at: closedAt)
        // マウスダウンで閉じ、マウスアップでアイコンの操作が届くまでの間隔を含める。
        #expect(!gate.shouldOpen(isShown: false, at: closedAt.addingTimeInterval(0.4)))
    }

    @Test func フォーカスを失って閉じてから間が空いた押下は_開く() {
        var gate = PopoverToggleGate()
        let closedAt = Date(timeIntervalSince1970: 1000)
        gate.recordClose(.focusLoss, at: closedAt)
        #expect(gate.shouldOpen(isShown: false, at: closedAt.addingTimeInterval(PopoverToggleGate.focusLossWindow + 0.01)))
    }

    @Test(arguments: [PopoverCloseReason.statusItem, .escape, .openSettings])
    func アイコンの押下で閉じうる理由以外で閉じた直後の押下は_開く(reason: PopoverCloseReason) {
        var gate = PopoverToggleGate()
        let closedAt = Date(timeIntervalSince1970: 1000)
        gate.recordClose(reason, at: closedAt)
        #expect(gate.shouldOpen(isShown: false, at: closedAt.addingTimeInterval(0.01)))
    }
}
