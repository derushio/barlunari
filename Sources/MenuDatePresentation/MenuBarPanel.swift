import AppKit
import SwiftUI

/// SwiftUI がウインドウをリサイズしない `NSHostingView`。内容の大きさが変わったことだけを知らせる。
///
/// `sizingOptions` を `intrinsicContentSize` だけにして、ウインドウの最小・最大の大きさや推奨の大きさを SwiftUI が決めないようにする。
/// ウインドウのフレームを書くのは `MenuBarPanel.updateFrame()` の 1 か所である。
@MainActor
public final class FittingHostingView<Root: View>: NSHostingView<Root> {
    /// 内容の大きさが変わった合図。レイアウトの最中に呼ばれることがあるので、受け取る側はフレームをその場で書かない。
    var onContentSizeInvalidated: (@MainActor () -> Void)?

    public required init(rootView: Root) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) は使わない")
    }

    override public func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onContentSizeInvalidated?()
    }
}

/// メニューやポップオーバーと同じ半透明の素材の背景。
private struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// メニューバーから出すパネル。枠なし、key になれる、アプリを前面にしない、影と角丸と半透明の素材の背景を持つ。
///
/// 大きさは内容に合わせ、位置は `PopoverPlacement` で決める。フレームを書くのは `updateFrame()` だけで、内容の大きさが変わったときは
/// レイアウトの最中ではなく次のランループで呼ぶ（`scheduleFrameUpdate()`）。上端の位置は動かさない。
@MainActor
public final class MenuBarPanel: NSPanel {
    /// 角丸の半径。
    public static let cornerRadius: CGFloat = 12

    public private(set) var anchor: PopoverAnchor?
    /// Esc が、ウインドウまで届く前に呼ばれる。SwiftUI の `onExitCommand` を経由せず、同じ規則で処理するため。
    public var onEscape: (@MainActor () -> Void)?
    /// key でなくなったときに呼ばれる。
    public var onResignKey: (@MainActor () -> Void)?

    private let measureContent: @MainActor () -> CGSize
    private var isFrameUpdateScheduled = false

    /// - Parameter rootView: パネルの中身。メニューやポップオーバーと同じ半透明の素材の背景と角丸は、パネルが付ける。
    public init<Root: View>(rootView: Root) {
        // 素材の背景と角丸は SwiftUI の側で付け、NSHostingView をウインドウの contentView にする。
        // contentView でない NSHostingView は、画面に出ていないと内容の大きさの変化を知らせないため。
        let hosting = FittingHostingView(
            rootView: rootView
                .background(PanelMaterial())
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        )
        measureContent = { hosting.fittingSize }
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        contentView = hosting
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // .statusBar 以下のレベルは、他のアプリのフルスクリーンの内容より下になり見えない。
        level = .screenSaver
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        hosting.onContentSizeInvalidated = { [weak self] in self?.scheduleFrameUpdate() }
    }

    /// key になれるか。アプリでは `true` で、開くときに key にする。操作ツールは利用者のフォーカスを奪わないため `false` にする。
    /// key になれるパネルが key でないときの最初のクリックは、パネルを key にするだけで中身に届かないので、
    /// key にしないパネルでは、すべてのクリックを中身に届けるためにも `false` にする。
    public var allowsKey = true

    override public var canBecomeKey: Bool { allowsKey }
    override public var canBecomeMain: Bool { false }

    override public func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Esc は、SwiftUI の View より先に受け取る。詳細や日の予定の一覧が開いているかの判断は `onEscape` の側で行う。
    override public func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    /// アプリが隠されていれば、アプリを有効にしないまま隠された状態を解く。パネルを前に出す前に呼ぶ。
    ///
    /// `open -j` やログイン時の起動で隠されて起動したアプリと、他のアプリの「ほかを隠す」で隠されたアプリでは、
    /// `orderFrontRegardless` を呼んでもパネルが画面に出ず、key にもならない。
    public func unhideApplicationIfNeeded() {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
    }

    // MARK: フレーム

    /// 置く基準を渡し、フレームを書く。
    public func place(at anchor: PopoverAnchor) {
        self.anchor = anchor
        updateFrame()
    }

    /// 内容の大きさに合わせて、次のランループでフレームを書き直す。同じランループの中の呼び出しは 1 回にまとめる。
    public func scheduleFrameUpdate() {
        guard !isFrameUpdateScheduled else { return }
        isFrameUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.isFrameUpdateScheduled = false
                self?.updateFrame()
            }
        }
    }

    /// パネルのフレームを書く唯一の場所。内容の大きさと基準からフレームを求め、変わるときだけ書く。上端は基準で決まり、動かない。
    public func updateFrame() {
        guard let anchor else { return }
        let target = PopoverPlacement.frame(contentSize: measureContent(), anchor: anchor)
        guard target != frame else { return }
        setFrame(target, display: true, animate: false)
        invalidateShadow()
    }
}
