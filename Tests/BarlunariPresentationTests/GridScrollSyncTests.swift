import Testing

@testable import BarlunariPresentation

/// 月のマス目のスクロールのうち、どの位置を表示月へ反映するか。
@Suite struct GridScrollSyncTests {
    @Test func 利用者のスクロールの位置は変わるたびに反映する() {
        var sync = GridScrollSync(topWeek: 10)

        #expect(sync.phaseDidChange(to: .interacting) == nil)
        #expect(sync.geometryDidChange(topWeek: 18) == 18)
        #expect(sync.geometryDidChange(topWeek: 25) == 25)
        #expect(sync.phaseDidChange(to: .idle) == 25)
    }

    @Test func 行への揃えのアニメーションの途中は反映せず止まったときに反映する() {
        var sync = GridScrollSync(topWeek: 10)

        _ = sync.phaseDidChange(to: .interacting)
        _ = sync.geometryDidChange(topWeek: 30)
        _ = sync.phaseDidChange(to: .decelerating)
        #expect(sync.phaseDidChange(to: .animating) == nil)
        #expect(sync.geometryDidChange(topWeek: 31) == nil)
        #expect(sync.phaseDidChange(to: .idle) == 31)
    }

    @Test func 一番上の週がすでに移動先と同じなら通知を待たずに着いたものとして終える() {
        var sync = GridScrollSync(topWeek: 40)

        sync.programmaticScroll(to: 40)

        let settled = sync.settleIfAlreadyAtTarget()
        let reported = sync.giveUp()

        #expect(settled)
        #expect(sync.pendingTarget == nil)
        #expect(reported == nil)
    }

    @Test func 一番上の週が移動先と違うか利用者が触れている間は着いたものとして終えない() {
        var sync = GridScrollSync(topWeek: 40)
        sync.programmaticScroll(to: 10)
        let settled = sync.settleIfAlreadyAtTarget()
        #expect(!settled)
        #expect(sync.pendingTarget == 10)

        var touching = GridScrollSync(topWeek: 40)
        _ = touching.phaseDidChange(to: .interacting)
        touching.programmaticScroll(to: 40)
        let settledWhileTouching = touching.settleIfAlreadyAtTarget()
        #expect(!settledWhileTouching)
    }

    @Test func プログラムからのスクロールの途中の位置は反映せず着いたら移動先を反映する() {
        var sync = GridScrollSync(topWeek: 40)

        sync.programmaticScroll(to: 10)
        #expect(sync.phaseDidChange(to: .animating) == nil)
        #expect(sync.geometryDidChange(topWeek: 30) == nil)
        #expect(sync.geometryDidChange(topWeek: 12) == nil)
        #expect(sync.geometryDidChange(topWeek: 10) == nil)
        #expect(sync.pendingTarget == nil)
        #expect(sync.phaseDidChange(to: .idle) == 10)
    }

    @Test func 移動先へ向かう間の止まった通知は古い位置を反映しない() {
        var sync = GridScrollSync(topWeek: 40)

        sync.programmaticScroll(to: 10)
        #expect(sync.phaseDidChange(to: .idle) == nil)
        #expect(sync.pendingTarget == 10)
    }

    @Test func アニメーションの途中で利用者がスクロールを始めたらidleのまま届く位置も反映する() {
        var sync = GridScrollSync(topWeek: 40)

        sync.programmaticScroll(to: 10)
        _ = sync.phaseDidChange(to: .animating)
        // フェーズだけが先に interacting、idle と進み、一番上の週の通知が idle のまま届く。
        #expect(sync.phaseDidChange(to: .interacting) == nil)
        #expect(sync.pendingTarget == nil)
        #expect(sync.phaseDidChange(to: .idle) == 40)
        #expect(sync.geometryDidChange(topWeek: 52) == 52)
        #expect(sync.geometryDidChange(topWeek: 60) == 60)
    }

    @Test func 利用者のスクロールの最中に移動を求められても利用者の位置を反映し続ける() {
        var sync = GridScrollSync(topWeek: 40)
        _ = sync.phaseDidChange(to: .interacting)

        sync.programmaticScroll(to: 10)
        #expect(sync.geometryDidChange(topWeek: 45) == 45)
        #expect(sync.pendingTarget == nil)
    }

    @Test func 移動先に着かないまま諦めたときはマス目の実際の位置を反映する() {
        var sync = GridScrollSync(topWeek: 40)
        _ = sync.geometryDidChange(topWeek: 62)

        sync.programmaticScroll(to: 10)
        #expect(sync.giveUp() == 62)
        #expect(sync.pendingTarget == nil)
        #expect(sync.giveUp() == nil)
    }
}
