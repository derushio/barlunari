import MenuDateDomain
import SwiftUI

/// 予定一覧のスクロール。一番上の日と ViewModel の選択日を同期する。
///
/// - 利用者のスクロールで一番上の日が変わったら、`agendaDidScroll(toTopDay:)` で選択日に反映する
/// - ViewModel が選択日を変えたら、`agendaScrollRequest` を受けて、その日の見出しを一番上に合わせる
///
/// 一覧の日の範囲は固定なので、先頭に日が足されたり削られたりして、内容の座標が動くことはない。
/// 一番上の日は `AgendaTopDayResolver` が、各セクションの上端（内容の座標）とスクロールのオフセットから求める。
/// セクションの位置は `AgendaListView` が測り、オフセットは `onScrollGeometryChange` で受ける。
/// 選択日に反映するのは、スクロールのフェーズが `.interacting` か `.decelerating` の間に一番上の日が変わったときと、
/// それらのフェーズから `.idle` に戻ったときと、戻ったあと位置の変化が `AgendaScrollGeometry.settleDuration` 途切れるまでに位置が変わったときである。
/// プログラムからのスクロールではフェーズが `.idle` のままで、始めるときに止まった直後の扱いも終えるので、選択日の更新には戻らない。
/// 利用者が触れたら、プログラムからのスクロールの合わせ直しはやめる。
///
/// プログラムからのスクロールは `ScrollViewReader` で行い、`ScrollPosition` は使わない。
/// `ScrollPosition` は、保持している ID やオフセットを内容が変わるたびに適用し直すので、ここで合わせた位置を上書きする。
/// この View の body は `agendaDayCount` だけを読む。選択日やスクロールの位置の変化で一覧全体を作り直さないよう、親の View から分けてある。
struct AgendaScrollView: View {
    let viewModel: CalendarPopoverViewModel

    /// セクションの位置、スクロールのオフセットとフェーズ。測定のたびに View を更新しないよう、`@Observable` にも `@State` の値にもしない。
    /// オフセットとフェーズを `@State` の値にすると、スクロールのたびとフェーズが変わるたびに body が再評価される。
    @State private var geometry = AgendaScrollGeometry()
    /// 見出しを一番上に合わせ直している処理。
    @State private var alignTask: Task<Void, Never>?

    /// 合わせ直す回数の上限。
    private static let maxAlignAttempts = 8
    /// 合わせ直す間隔。測り直されるのを待つ。
    private static let alignInterval: Duration = .milliseconds(30)
    /// 見出しが一番上に来たとみなす誤差。
    private static let alignTolerance: CGFloat = 0.5

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                AgendaListView(viewModel: viewModel, dayCount: viewModel.agendaDayCount, geometry: geometry)
            }
            .onScrollGeometryChange(for: CGFloat.self) { scrollGeometry in
                scrollGeometry.contentOffset.y + scrollGeometry.contentInsets.top
            } action: { _, offset in
                geometry.offset = offset
                if isUserScrolling(geometry.phase) {
                    reportTopDay()
                } else if geometry.isSettlingAfterUserScroll {
                    // 残りの動きが続く間は、期限を延ばし続ける。
                    geometry.settleAfterUserScroll()
                    reportTopDay()
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                geometry.phase = newPhase
                // 利用者が触れたら、見出しの合わせ直しをやめる。続けると、利用者が動かした一覧を合わせ直しの日へ戻す。
                if isUserScrolling(newPhase) { alignTask?.cancel() }
                if isUserScrolling(oldPhase), newPhase == .idle {
                    geometry.settleAfterUserScroll()
                    reportTopDay()
                }
            }
            .onChange(of: viewModel.agendaScrollRequest) { _, request in
                guard let request else { return }
                scrollAligned(to: request.day, using: proxy)
            }
            // 作り直されたときも、選択日を一番上にして始める。
            .onAppear {
                // 測定の更新は描画の最中に届くので、状態の更新は次の実行に回す。
                geometry.onTopsChange = {
                    guard geometry.hasPendingReport else { return }
                    Task { @MainActor in if geometry.hasPendingReport { reportTopDay() } }
                }
                scrollAligned(to: viewModel.selectedDay, using: proxy)
            }
        }
    }

    /// `day` の見出しを一番上にスクロールし、一番上に来るまで合わせ直す。
    ///
    /// `LazyVStack` は、まだ作っていないセクションの高さを推定で扱う。番号を指定したスクロールは、その推定で位置を決めるので、
    /// 移動先のセクションが作られて本当の高さになると、見出しが一番上からずれる。セクションの上端を測り、ずれていれば同じ番号へもう一度スクロールする。
    /// 位置が動かなくなったら（一覧の末尾で止まった場合）やめる。
    private func scrollAligned(to day: CalendarDay, using proxy: ScrollViewProxy) {
        guard let index = viewModel.agendaIndex(of: day) else { return }
        geometry.hasPendingReport = false
        geometry.endSettling()
        alignTask?.cancel()
        proxy.scrollTo(index, anchor: .top)
        alignTask = Task {
            var previous = geometry.offset
            for _ in 0..<Self.maxAlignAttempts {
                try? await Task.sleep(for: Self.alignInterval)
                if Task.isCancelled { return }
                let top = geometry.sectionTop(of: index)
                if let top, abs(top - geometry.offset) < Self.alignTolerance { return }
                proxy.scrollTo(index, anchor: .top)
                // 位置が動かなくなったら、一覧の末尾で止まっている。
                if geometry.offset == previous, top != nil { return }
                previous = geometry.offset
            }
        }
    }

    private func isUserScrolling(_ phase: ScrollPhase) -> Bool {
        phase == .interacting || phase == .decelerating
    }

    /// 現在のオフセットで一番上にある日を、選択日に反映する。同じ日なら ViewModel 側で何も起きない。
    ///
    /// スクロールのたびに呼ばれるので、セクションの表示内容を読まない。
    ///
    /// 大きくスクロールした直後は、移動先のセクションの測定がスクロールに追いついていない。そのときは一番上の日が求められないので、
    /// 測定が更新されたとき（`AgendaScrollGeometry.onTopsChange`）に、改めて反映する。反映しないまま止まると、一覧の位置と選択日がずれる。
    private func reportTopDay() {
        geometry.hasPendingReport = true
        guard geometry.resolver.covers(geometry.offset, firstIndex: 0, lastIndex: viewModel.agendaDayCount - 1) else { return }
        geometry.hasPendingReport = false
        guard let index = geometry.resolver.topDayIndex(at: geometry.offset), let day = viewModel.agendaDay(at: index) else { return }
        viewModel.agendaDidScroll(toTopDay: day)
    }
}

/// `AgendaScrollView` が測ったセクションの位置とスクロールのオフセット。上端が変わるまで、`AgendaTopDayResolver` を使い回す。
///
/// 測るのは `LazyVStack` が作っているセクションだけで、作られなくなったセクションの位置は残さない。
@MainActor
final class AgendaScrollGeometry {
    private var tops: [Int: CGFloat] = [:]
    private var cached: AgendaTopDayResolver?
    /// 内容の座標でのビューポートの上端。
    var offset: CGFloat = 0
    var phase: ScrollPhase = .idle
    /// 一番上の日を選択日へ反映できていない。測定が追いついたときに反映する。
    var hasPendingReport = false
    /// 利用者のスクロールが止まってから、位置の変化を選択日へ反映し続ける期限（`systemUptime`）。
    private var settleDeadline: TimeInterval = 0

    /// 利用者のスクロールの直前にプログラムからのスクロールを求めると、macOS は利用者のスクロールのフェーズを途中で `.idle` に戻し、
    /// 残りの動きを `.idle` のまま一覧に反映する。その位置を選択日へ反映しないと、一覧と選択日が食い違うので、
    /// 利用者のスクロールが止まったあと、位置の変化が `settleDuration` 途切れるまでは、`.idle` の位置の変化も利用者のスクロールとして扱う。
    static let settleDuration: TimeInterval = 0.5

    /// 利用者のスクロールが止まった直後で、位置の変化を選択日へ反映する間か。
    var isSettlingAfterUserScroll: Bool {
        phase == .idle && ProcessInfo.processInfo.systemUptime < settleDeadline
    }

    func settleAfterUserScroll() {
        settleDeadline = ProcessInfo.processInfo.systemUptime + Self.settleDuration
    }

    /// プログラムからのスクロールを始めるときに呼ぶ。その移動は選択日へ伝え返さない。
    func endSettling() {
        settleDeadline = 0
    }
    /// 測定したセクションの位置が変わったときに呼ぶ。
    var onTopsChange: (() -> Void)?

    /// 作られているセクションの位置で入れ替える。
    func replace(_ newTops: [Int: CGFloat]) {
        guard tops != newTops else { return }
        tops = newTops
        cached = nil
        onTopsChange?()
    }

    /// セクションの見出しの上端。直前のセクションとの間の余白は含めない。
    func sectionTop(of index: Int) -> CGFloat? {
        tops[index].map { $0 + AgendaListView.sectionSpacing }
    }

    var resolver: AgendaTopDayResolver {
        if let cached { return cached }
        let resolver = AgendaTopDayResolver(tops: tops)
        cached = resolver
        return resolver
    }
}
