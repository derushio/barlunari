import AppKit
import SwiftUI

/// 操作が止まっていたあとの最初の `Canvas` の描画を、スクロールの最初の行を作るフレームから外すための仕組み。
///
/// 数秒以上描画が止まっていたあとの最初の `Canvas` の描画は、描く内容によらず、およそ 50M 命令（ミリ秒で 7ms 前後）余計にかかる。
/// 何も見えない 1 つの `Canvas` を、スクロールが始まったとき（と、マス目の上にカーソルが入ったとき）に先に描いておくと、
/// この余計な処理はそのフレームで済み、行を作るフレームには載らない。
///
/// ウインドウが画面に出ている間は、マス目の上にカーソルがなくても `keepWarmInterval` ごとに先に描いておく。カーソルが動かずに
/// スクロールが始まる場合（ポップオーバーを開いたままの待機、表示モードの切り替え直後）に、最初のスクロールのフレームへ載るのを避けるため。
/// ウインドウが隠れている間は、タイマーを動かさない。
@MainActor
@Observable
final class CanvasWarmup {
    /// 描き直しの合図。値が変わると `CanvasWarmupView` の `Canvas` を描き直す。
    private(set) var tick = 0
    @ObservationIgnored private var lastRequest = ContinuousClock.now
    @ObservationIgnored private var visibilityObservation: NSKeyValueObservation?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var keepWarmTask: Task<Void, Never>?
    /// 月表示で、見えている週の前後の週を先に用意する仕組み。コンパクト表示では `nil`。
    @ObservationIgnored var preparation: MonthIdlePreparation?
    /// 先に用意する週の中心（一番上に一部でも見えている週）と、行の大きさ。`WeekScrollView` が更新する。
    @ObservationIgnored var preparationPlace: (firstVisibleWeek: Int, size: CGSize, colorScheme: ColorScheme, displayScale: CGFloat)?
    /// スクロールの途中。先に用意する処理は、スクロールの途中では行わない。
    @ObservationIgnored private(set) var isScrolling = false
    @ObservationIgnored private var scrollEndTask: Task<Void, Never>?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?

    /// 載っているウインドウを知らせる。画面に出ている間だけ、定期的に先に描く。`nil` なら止める。
    func attach(to window: NSWindow?) {
        visibilityObservation = nil
        keepWarmTask?.cancel()
        keepWarmTask = nil
        self.window = window
        guard let window else { return }
        visibilityObservation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] _, change in
            let isVisible = change.newValue ?? false
            MainActor.assumeIsolated { self?.windowVisibilityDidChange(isVisible) }
        }
    }

    private func windowVisibilityDidChange(_ isVisible: Bool) {
        keepWarmTask?.cancel()
        keepWarmTask = nil
        guard isVisible else {
            // 隠れている間は、画像のメモリを手放す。
            preparationTask?.cancel()
            preparationTask = nil
            preparation?.releaseImages()
            return
        }
        warmDisplayLink()
        keepWarmTask = Task { @MainActor [weak self] in
            // 表示された直後にも、先に用意する。予定の読み込みが済んでいなければ、次の周期でやり直す。
            try? await Task.sleep(for: Self.firstPreparationDelay)
            self?.requestPreparation()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.keepWarmInterval)
                guard let self else { return }
                request()
                requestPreparation()
            }
        }
    }

    /// ウインドウのディスプレイリンクを作って、すぐに破棄する。
    ///
    /// スクロールの始まりで AppKit（`NSScrollingAnimator`）が最初にディスプレイリンクを作るとき、ディスプレイの情報
    /// （`CADisplay` の初期化と、ディスプレイモードの一覧の取得）を読み込む。この処理が最初のスクロールのフレームに
    /// 30M 命令ほど載るので、ウインドウが出た直後のアイドル時に先に済ませる。
    func warmDisplayLink() {
        guard let window else { return }
        let link = window.displayLink(target: DisplayLinkSink.shared, selector: #selector(DisplayLinkSink.fire(_:)))
        link.invalidate()
    }

    /// スクロールの始まりと終わりを知らせる。始まりでは先描きを求める。終わりから `preparationDelayAfterScroll` たってもスクロールが再開しなければ、先に用意する。
    func scrollingDidChange(_ isScrolling: Bool) {
        self.isScrolling = isScrolling
        if isScrolling {
            preparationTask?.cancel()
            preparationTask = nil
        }
        scrollEndTask?.cancel()
        scrollEndTask = nil
        if isScrolling {
            request()
            return
        }
        scrollEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.preparationDelayAfterScroll)
            guard !Task.isCancelled else { return }
            self?.requestPreparation()
        }
    }

    /// 見えている週の前後の週の画像を、先に用意するよう求める。用意するものがなければ何もしない。
    /// 用意は、時間の上限の範囲ごとに、少し間を置いて続ける。スクロールが始まったら止める。
    func requestPreparation() {
        guard !isScrolling, preparationTask == nil, preparation != nil, preparationTarget() != nil else { return }
        preparationTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, !isScrolling, let preparation, let target = preparationTarget(), preparation.needsWork(target) {
                if preparation.prepare(target, budget: Self.preparationBudget) { break }
                try? await Task.sleep(for: Self.continuationInterval)
            }
            self?.preparationTask = nil
        }
    }

    private func preparationTarget() -> MonthIdlePreparation.Target? {
        guard let preparation, let place = preparationPlace, place.size.width > 0 else { return nil }
        let target = preparation.target(
            firstVisibleWeek: place.firstVisibleWeek, size: place.size, colorScheme: place.colorScheme, displayScale: place.displayScale
        )
        return preparation.needsWork(target) ? target : nil
    }

    /// 先に描いておく。直前の要求から `minimumInterval` 以内なら、描画は止まっていないので何もしない。
    func request() {
        let now = ContinuousClock.now
        guard now - lastRequest >= Self.minimumInterval else { return }
        lastRequest = now
        tick += 1
    }

    /// 描画が止まっていたとみなす間隔。0.3 秒の間隔では余計な処理がかからず、3 秒の間隔ではかかる。
    private static let minimumInterval: Duration = .milliseconds(500)
    /// ウインドウが出ている間に、先に描く間隔。描画が止まったとみなされる 3 秒より十分短くする。
    private static let keepWarmInterval: Duration = .seconds(1)
    /// ウインドウが出てから、最初に先に用意するまでの間隔。
    private static let firstPreparationDelay: Duration = .milliseconds(100)
    /// スクロールが終わってから、先に用意し始めるまでの間隔。続けてスクロールを始める操作に、用意の処理を重ねないため。
    private static let preparationDelayAfterScroll: Duration = .milliseconds(250)
    /// 1 回の描画で先に用意する時間の上限。超えたら続きを次の描画に回す。
    private static let preparationBudget: Duration = .milliseconds(3)
    /// 続きを用意する間隔。
    private static let continuationInterval: Duration = .milliseconds(30)
}

/// 何も見えない `Canvas`。`CanvasWarmup` の合図で描き直す。
struct CanvasWarmupView: View {
    let warmup: CanvasWarmup

    var body: some View {
        let tick = warmup.tick
        Canvas { context, size in
            // ほぼ透明な小さな四角を塗る。完全な透明だと描画が省かれる恐れがあるので、わずかに不透明にする。
            if tick > 0 { context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.01))) }
        }
        .frame(width: 2, height: 2)
        .background(WarmupWindowProbe(warmup: warmup))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// `CanvasWarmup` に、載っているウインドウを知らせる。
private struct WarmupWindowProbe: NSViewRepresentable {
    let warmup: CanvasWarmup

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.warmup = warmup
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        var warmup: CanvasWarmup?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            warmup?.attach(to: window)
        }
    }
}

/// `warmDisplayLink` が作るディスプレイリンクの受け手。リンクはすぐ破棄するので、呼ばれない。
@MainActor
private final class DisplayLinkSink: NSObject {
    static let shared = DisplayLinkSink()
    @objc func fire(_ link: CADisplayLink) {}
}
