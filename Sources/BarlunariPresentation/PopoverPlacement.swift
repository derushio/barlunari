import CoreGraphics

/// ディスプレイ 1 枚の範囲。`NSScreen` の `frame` と `visibleFrame` を写す。座標は AppKit と同じ左下原点で、複数のディスプレイは 1 つの座標系に並ぶ。
public struct DisplayGeometry: Equatable, Sendable {
    public let frame: CGRect
    /// Dock とメニューバーを除いた範囲。外部ディスプレイでは `frame` と同じことがある（上端のメニューバーが除かれない）。
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// パネルを置く基準。クリックの x、メニューバーの下端の y、置くディスプレイの `visibleFrame`。
public struct PopoverAnchor: Equatable, Sendable {
    public let clickX: CGFloat
    public let menuBarBottom: CGFloat
    public let visibleFrame: CGRect

    public init(clickX: CGFloat, menuBarBottom: CGFloat, visibleFrame: CGRect) {
        self.clickX = clickX
        self.menuBarBottom = menuBarBottom
        self.visibleFrame = visibleFrame
    }
}

/// パネルを出すディスプレイと、そこでの基準。
public struct PopoverPlan: Equatable, Sendable {
    public let displayIndex: Int
    public let anchor: PopoverAnchor
    /// メニューバーの下から Dock の上まで。月表示の大きさ（`MonthPopoverSizing`）を決める。
    public let visibleArea: CGRect
}

/// メニューバーのパネルの位置の計算。AppKit に依存しない純粋な関数だけを持つ。座標は AppKit と同じ左下原点である。
///
/// - 出すディスプレイ: クリックの位置があるディスプレイ。どこにもなければ、ボタンのウインドウがあるディスプレイ、なければ先頭のディスプレイ
/// - 縦: パネルの上端を、メニューバーの下端から `gap` 下げた位置に置く。内容の高さが変わっても上端は動かさず、下端が動く
/// - 横: パネルの横の中心をクリックの x に合わせ、可視領域の左右の `edgeMargin` の内側に収める
/// - 可視領域より大きいパネルは、可視領域の余白の内側に収まる大きさに縮める
public enum PopoverPlacement {
    /// 可視領域の端から空ける余白。
    public static let edgeMargin: CGFloat = 8
    /// メニューバーの下端とパネルの上端の間隔。
    public static let gap: CGFloat = 4

    /// `point` を含む最初のディスプレイの番号。
    public static func displayIndex(containing point: CGPoint, in displays: [DisplayGeometry]) -> Int? {
        displays.firstIndex { $0.frame.contains(point) }
    }

    /// メニューバーの下端の y。
    ///
    /// `visibleFrame` の上端がメニューバーを除いていれば（`frame` の上端より低ければ）それを使う。除いていないとき（外部ディスプレイで `frame` と同じ）は、
    /// ボタンのウインドウの中心がそのディスプレイにあればその下端、なければ `frame` の上端からメニューバーの高さを引いた位置にする。
    public static func menuBarBottom(
        of display: DisplayGeometry, buttonFrame: CGRect?, menuBarThickness: CGFloat
    ) -> CGFloat {
        if display.visibleFrame.maxY < display.frame.maxY - 0.5 {
            return display.visibleFrame.maxY
        }
        if let buttonFrame, display.frame.contains(CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)) {
            return min(buttonFrame.minY, display.frame.maxY)
        }
        return display.frame.maxY - menuBarThickness
    }

    /// 月表示の大きさを決める領域。メニューバーの下から Dock の上まで。
    public static func visibleArea(of display: DisplayGeometry, menuBarBottom: CGFloat) -> CGRect {
        let bottom = display.visibleFrame.minY
        return CGRect(
            x: display.visibleFrame.minX, y: bottom,
            width: display.visibleFrame.width, height: max(0, menuBarBottom - bottom)
        )
    }

    /// 月表示のパネルの内容の大きさ。`visibleArea` に余白を引いて収め、下限を下回らせない（`MonthPopoverSizing`）。
    public static func monthContentSize(in visibleArea: CGRect) -> CGSize {
        MonthPopoverSizing.size(visibleFrame: visibleArea)
    }

    /// クリックの位置から、パネルを出すディスプレイと基準を決める。ディスプレイがなければ `nil`。
    public static func plan(
        click: CGPoint, displays: [DisplayGeometry], buttonFrame: CGRect?, menuBarThickness: CGFloat
    ) -> PopoverPlan? {
        guard !displays.isEmpty else { return nil }
        let clickIndex = displayIndex(containing: click, in: displays)
        let buttonIndex = buttonFrame.flatMap { displayIndex(containing: CGPoint(x: $0.midX, y: $0.midY), in: displays) }
        let index = clickIndex ?? buttonIndex ?? 0
        let display = displays[index]
        let bottom = menuBarBottom(of: display, buttonFrame: buttonFrame, menuBarThickness: menuBarThickness)
        // クリックがどのディスプレイにもないとき（キーボードでの操作など）は、ボタンの中心に合わせる。
        let x = clickIndex == nil ? (buttonFrame?.midX ?? click.x) : click.x
        return PopoverPlan(
            displayIndex: index,
            anchor: PopoverAnchor(clickX: x, menuBarBottom: bottom, visibleFrame: display.visibleFrame),
            visibleArea: visibleArea(of: display, menuBarBottom: bottom)
        )
    }

    /// パネルのフレーム。上端は `anchor.menuBarBottom - gap` で固定し、`contentSize` が変わっても動かさない。
    public static func frame(contentSize: CGSize, anchor: PopoverAnchor) -> CGRect {
        let visible = anchor.visibleFrame
        let minX = visible.minX + edgeMargin
        let maxX = visible.maxX - edgeMargin
        let width = max(0, min(contentSize.width, maxX - minX))
        let x = min(max(anchor.clickX - width / 2, minX), maxX - width)

        let top = anchor.menuBarBottom - gap
        let bottom = visible.minY + edgeMargin
        let height = max(0, min(contentSize.height, top - bottom))
        return CGRect(x: x, y: top - height, width: width, height: height)
    }
}
