import MenuDateDomain
import SwiftUI

/// `WeekScrollView` の調整値。ジェネリックな型は static な格納プロパティを持てないので、ここに置く。
private enum WeekScrollTuning {
    /// スクロールし直す回数の上限。
    static let maxRetries = 4
    /// スクロールし直す間隔。アニメーションの長さ（0.3 秒）より長くする。
    static let retryInterval: Duration = .milliseconds(400)
    /// 見えている週の前後に、余分に描いておく週の数。速いスクロールで、描く前の行が見えないようにする。
    static let overscanWeeks = 2
}

/// 週の行が連続して流れる縦のスクロール。コンパクト表示のマス目と月表示のマス目が共有する。
///
/// 週の行は、見えている週とその前後の数週だけを `WeekRowsLayout` で固定の位置に置き、縦の `ScrollView` に入れる。
/// 見えているのは 6 週で、行の境目には揃えず、指を離した位置で止まる。
///
/// - 利用者のスクロールで一番上の週が変わったら、`gridDidScroll(toTopWeek:)` で表示月に反映する
/// - ViewModel が表示月を変えたら、`gridScrollRequest` を受けて、その月の最初の週を一番上にスクロールする
///
/// どの位置を表示月へ反映するかは `GridScrollSync` が決める。プログラムからのスクロールの途中の位置は、表示月へ伝え返さない。
/// 行は自分の週の日だけを ViewModel から読むので、選択日などが変わっても再評価されるのは見えている行だけである。
///
/// 行の View を作る `row` が、パネルの開閉などで変わる値をキャプチャすると、変わるたびに全行が評価し直される。
/// `row` には、ViewModel と週の番号から行を作る処理だけを渡す。
struct WeekScrollView<Row: View>: View {
    let viewModel: CalendarPopoverViewModel
    /// 週の行の高さ。変わったときは、そのときの一番上の週を保ってスクロールし直す。
    let rowHeight: CGFloat
    /// スクロールの枠の高さ。
    let viewportHeight: CGFloat
    /// 週の番号の行を作る。
    let row: (Int) -> Row
    /// 月表示で、操作が止まっている間に、見えている週の前後の週の予定の配置と文字を先に用意するか。
    let preparesMonthEvents: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var position: ScrollPosition
    /// スクロールの状態。変わるたびに View を更新しないよう、`@Observable` にしない。
    @State private var sync = GridScrollSync(topWeek: 0)
    /// 最初に一番上に置く週。
    private let initialWeek: Int
    /// 一番上に一部でも見えている週。描く行の範囲を決める。行の境目を越えたときだけ変わる。
    @State private var firstVisibleWeek: Int
    /// 移動先に着くまで、スクロールし直している処理。
    @State private var retryTask: Task<Void, Never>?
    /// 描画が止まっていたあとの最初の描画を先に済ませる。
    @State private var warmup = CanvasWarmup()
    /// 行の幅。先に用意する文字の幅を、描くときと同じにするために使う。
    @State private var width: CGFloat = 0

    init(
        viewModel: CalendarPopoverViewModel, rowHeight: CGFloat, viewportHeight: CGFloat, preparesMonthEvents: Bool = false,
        @ViewBuilder row: @escaping (Int) -> Row
    ) {
        self.preparesMonthEvents = preparesMonthEvents
        self.viewModel = viewModel
        self.rowHeight = rowHeight
        self.viewportHeight = viewportHeight
        self.row = row
        let week = viewModel.initialGridWeek
        _position = State(initialValue: ScrollPosition(idType: Int.self))
        // 初期の位置を適用するまでの位置（先頭）を、表示月へ伝えないようにする。
        var sync = GridScrollSync(topWeek: week)
        sync.programmaticScroll(to: week)
        _sync = State(initialValue: sync)
        _firstVisibleWeek = State(initialValue: week)
        initialWeek = week
    }

    /// 描く週の範囲。見えている 6 週と、一部だけ見える 1 週と、その前後の `overscanWeeks` 週。
    private var renderedWeeks: Range<Int> {
        let lower = max(0, firstVisibleWeek - WeekScrollTuning.overscanWeeks)
        let upper = min(viewModel.weekCount, firstVisibleWeek + WeekTimeline.visibleWeekCount + 1 + WeekScrollTuning.overscanWeeks)
        return lower..<max(lower, upper)
    }

    var body: some View {
        ScrollView {
            WeekRowsLayout(rowHeight: rowHeight, firstWeek: renderedWeeks.lowerBound, weekCount: viewModel.weekCount) {
                ForEach(renderedWeeks, id: \.self) { index in
                    row(index)
                }
            }
        }
        .scrollIndicators(.never)
        .scrollPosition($position)
        .frame(height: viewportHeight)
        .onScrollGeometryChange(for: Int.self) { [rowHeight] geometry in
            Int(((geometry.contentOffset.y + geometry.contentInsets.top) / rowHeight).rounded(.down))
        } action: { _, week in
            firstVisibleWeek = week
            updatePreparationPlace()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            width = newWidth
            updatePreparationPlace()
        }
        .onScrollGeometryChange(for: Int.self) { [rowHeight] geometry in
            Int(((geometry.contentOffset.y + geometry.contentInsets.top) / rowHeight).rounded())
        } action: { _, week in
            if let reported = sync.geometryDidChange(topWeek: week) { viewModel.gridDidScroll(toTopWeek: reported) }
        }
        .overlay(alignment: .topLeading) { CanvasWarmupView(warmup: warmup) }
        .onContinuousHover { _ in warmup.request() }
        .onScrollPhaseChange { _, newPhase in
            warmup.scrollingDidChange(newPhase != .idle)
            if let reported = sync.phaseDidChange(to: Self.syncPhase(newPhase)) { viewModel.gridDidScroll(toTopWeek: reported) }
        }
        // 初期値に位置を持たせると、内容を配置する前に適用されて 0 に切り詰められるので、表示されたときに設定する。
        .onAppear {
            position.scrollTo(y: CGFloat(initialWeek) * rowHeight)
            if preparesMonthEvents { warmup.preparation = MonthIdlePreparation(viewModel: viewModel) }
            updatePreparationPlace()
        }
        .onChange(of: rowHeight) { updatePreparationPlace() }
        .onChange(of: colorScheme) { updatePreparationPlace(); warmup.requestPreparation() }
        .onChange(of: displayScale) { updatePreparationPlace(); warmup.requestPreparation() }
        .onChange(of: viewModel.gridScrollRequest) { _, request in
            guard let request else { return }
            // 移動の途中の通知が古い位置を表示月へ戻さないよう、移動先を先に記録する。
            sync.programmaticScroll(to: request.weekIndex)
            scroll(toWeek: request.weekIndex)
            scrollUntilArrived(atWeek: request.weekIndex)
        }
        // 行の高さが変わったら、変わる前の一番上の週を保つ。行の高さが変わる途中の位置を、表示月へ伝え返さない。
        .onChange(of: rowHeight) {
            let week = sync.topWeek
            sync.programmaticScroll(to: week)
            position.scrollTo(y: CGFloat(week) * rowHeight)
            scrollUntilArrived(atWeek: week)
        }
    }

    /// 先に用意する週の中心と行の大きさを、先描きの仕組みへ伝える。
    private func updatePreparationPlace() {
        guard preparesMonthEvents else { return }
        warmup.preparationPlace = (firstVisibleWeek, CGSize(width: width, height: rowHeight), colorScheme, displayScale)
    }

    /// 移動先に着くまで、少し待ってはスクロールし直す。利用者のスクロールの余韻の最中に求めたスクロールは、動かずに止まる。
    /// 同じ位置を続けて求めても動かないので、移動先の位置を 1pt ずつずらす。着く前に利用者が触れたり、次の要求が来たりしたら、やめる。
    private func scrollUntilArrived(atWeek week: Int) {
        retryTask?.cancel()
        retryTask = Task { @MainActor in
            for attempt in 1...WeekScrollTuning.maxRetries {
                try? await Task.sleep(for: WeekScrollTuning.retryInterval)
                if Task.isCancelled { return }
                // 移動先が今の一番上の週と同じだと、着いても一番上の週の通知が来ない。ずらして求め直さず、ずらさない位置に合わせて終える。
                // 半行以内のずれは一番上の週を変えないので、着いていても位置が合っているとは限らない。
                if sync.settleIfAlreadyAtTarget() {
                    scroll(toWeek: week)
                    return
                }
                if sync.pendingTarget == nil {
                    // ずらした位置で着いたときは、ずらさない位置に直す。利用者が触れて打ち切ったときは動かさない。
                    if attempt > 1, sync.topWeek == week, !sync.phase.isUserDriven {
                        position.scrollTo(y: CGFloat(week) * rowHeight)
                    }
                    return
                }
                scroll(toWeek: week, offsetBias: CGFloat(attempt))
            }
            try? await Task.sleep(for: WeekScrollTuning.retryInterval)
            if Task.isCancelled { return }
            if let reported = sync.giveUp() { viewModel.gridDidScroll(toTopWeek: reported) }
        }
    }

    /// - Parameter offsetBias: 移動先の位置に足すずれ。
    private func scroll(toWeek week: Int, offsetBias: CGFloat = 0) {
        let target = CGFloat(week) * rowHeight + offsetBias
        if reduceMotion {
            position.scrollTo(y: target)
        } else {
            withAnimation(.snappy(duration: 0.3)) { position.scrollTo(y: target) }
        }
    }

    private static func syncPhase(_ phase: ScrollPhase) -> GridScrollSync.Phase {
        switch phase {
        case .idle: .idle
        case .tracking: .tracking
        case .animating: .animating
        case .interacting: .interacting
        case .decelerating: .decelerating
        @unknown default: .idle
        }
    }
}

/// 週の行を、週の番号から決まる固定の位置に置く。大きさは全週分の高さで、子の大きさを問い合わせない。
///
/// `VStack` や `LazyVStack` は、配置のたびに子の大きさを測る。スクロールで描く行が入れ替わるたびに全行を測り直すと、
/// フレームに間に合わなくなるので、行の高さが固定であることを使って測らずに置く。
struct WeekRowsLayout: Layout {
    let rowHeight: CGFloat
    /// 最初の子の週の番号。子は週の番号の順に並んでいる。
    let firstWeek: Int
    let weekCount: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: CGFloat(weekCount) * rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rowProposal = ProposedViewSize(width: bounds.width, height: rowHeight)
        for (offset, subview) in subviews.enumerated() {
            let y = bounds.minY + CGFloat(firstWeek + offset) * rowHeight
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: rowProposal)
        }
    }
}
