/// 月のマス目のスクロールの位置から、表示月へ反映する週を決める。SwiftUI に依存しない。
///
/// `MonthGridView` が、スクロールのフェーズと一番上の週の通知をここへ渡し、返ってきた週を `gridDidScroll(toTopWeek:)` に渡す。
///
/// - プログラムからのスクロール（`programmaticScroll(to:)`）は、移動先に着くまで、途中の週を反映しない。途中の週を反映すると、
///   表示月が移動先の月から外れる
/// - 利用者が触れたら（`interacting`、`decelerating`）、プログラムからのスクロールは途中でも打ち切り、以後の週を反映する。
///   アニメーションの途中でスクロールを始めると、フェーズが `animating`、`interacting`、`idle` と進んだあとで、一番上の週の通知が
///   `idle` のまま届く。フェーズだけで反映を決めると、この通知を捨てて、表示月がマス目の位置に追従しなくなる
/// - プログラムからのスクロールが、移動先に着かないまま止まったら（利用者のスクロールの余韻の最中に求めると、アニメーションが
///   動かずに `idle` へ戻る）、`MonthGridView` が少し待ってスクロールし直す。着かないまま諦めたときは `giveUp()` で、
///   マス目の実際の位置を反映する
/// - アニメーション（`animating`）の途中は反映せず、止まったとき（`idle`）に反映する
struct GridScrollSync: Equatable {
    enum Phase: Equatable {
        case idle
        case tracking
        case animating
        case interacting
        case decelerating

        var isUserDriven: Bool { self == .interacting || self == .decelerating }
    }

    /// 通知された一番上の週。
    private(set) var topWeek: Int
    private(set) var phase: Phase = .idle
    /// プログラムからのスクロールの移動先の週。着くか、利用者が触れるか、`giveUp()` を呼ぶまで残る。
    private(set) var pendingTarget: Int?


    init(topWeek: Int) { self.topWeek = topWeek }

    /// プログラムからのスクロールを始める。移動先に着くまでの途中の週は反映しない。
    mutating func programmaticScroll(to week: Int) {
        pendingTarget = week
    }

    /// フェーズが変わった。表示月へ反映する週があれば返す。
    mutating func phaseDidChange(to newPhase: Phase) -> Int? {
        phase = newPhase
        if newPhase.isUserDriven { pendingTarget = nil }
        // 移動先へ向かっている間の止まった通知は、古い位置を返すので反映しない。
        return newPhase == .idle && pendingTarget == nil ? topWeek : nil
    }

    /// 一番上の週が変わった。表示月へ反映する週があれば返す。
    mutating func geometryDidChange(topWeek week: Int) -> Int? {
        topWeek = week
        if phase.isUserDriven { pendingTarget = nil }
        if let target = pendingTarget {
            if week == target { pendingTarget = nil }
            return nil
        }
        // アニメーションの途中は反映しない。止まったときに反映する。
        return phase == .animating ? nil : week
    }

    /// 一番上の週がすでに移動先と同じなら、プログラムからのスクロールを着いたものとして終え、`true` を返す。
    ///
    /// 移動先が今の一番上の週と同じだと、スクロールしても一番上の週が変わらず `geometryDidChange` が呼ばれないので、着いたことを検出できない。
    /// 利用者が触れている間は、移動先は既に捨てているので何もしない。
    mutating func settleIfAlreadyAtTarget() -> Bool {
        guard let target = pendingTarget, target == topWeek, !phase.isUserDriven else { return false }
        pendingTarget = nil
        return true
    }

    /// 移動先へのスクロールを諦める。マス目の実際の位置を、表示月へ反映する週として返す。移動先が残っていないときは `nil`。
    mutating func giveUp() -> Int? {
        guard pendingTarget != nil else { return nil }
        pendingTarget = nil
        return topWeek
    }
}
