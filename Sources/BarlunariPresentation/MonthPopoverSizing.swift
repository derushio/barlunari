import CoreGraphics
import BarlunariDomain

/// 月表示のポップオーバーの大きさと、その中の寸法。SwiftUI に依存しない。
///
/// 大きさは、ポップオーバーを出す画面の可視領域（`NSScreen.visibleFrame`）から求める。目標の大きさを、可視領域から余白を引いた大きさに収め、
/// 下限を下回らせない。週の行の高さは、マス目に使える高さを 6 で割った値（小数を切り捨て）である。
///
/// 幅は、マス目の幅（`targetGridWidth`）を保ったまま、右に日の欄（`dayPaneWidth`）と区切り線（`paneDividerWidth`）、
/// さらに右に予定の詳細の列（`detailColumnWidth`）と区切り線を足した値である。
/// 可視領域が狭いときに縮むのはマス目の幅で、日の欄と詳細の列の幅は変えない。
/// 余白を引いた可視領域の幅が 3 列の下限（`threeColumnMinimumWidth`）に届かないときは、詳細の列を出さず 2 列にする（`layout(visibleFrame:)`）。
enum MonthPopoverSizing {
    /// 月表示の列の構成。
    enum PaneLayout: Equatable {
        /// マス目と日の欄。詳細と表示するカレンダーの一覧は、日の欄でスケジュールと入れ替える。
        case twoColumn
        /// マス目、日の欄、詳細の列。日の欄は常にスケジュールを出し、詳細と一覧は詳細の列に出す。
        case threeColumn
    }

    /// 日の欄の幅。
    static let dayPaneWidth: CGFloat = 380
    /// 日の欄の左右の余白。
    static let dayPaneLeadingInset: CGFloat = 12
    static let dayPaneTrailingInset: CGFloat = 8
    /// 詳細の内容の高さの上限を求めるために、ポップオーバーの高さから引く値（上下の余白と戻るボタン）。
    static let dayPaneChromeHeight: CGFloat = 100
    /// マス目と日の欄を分ける区切り線の幅。
    static let paneDividerWidth: CGFloat = 1
    /// 日の欄と区切り線の幅の合計。
    static let dayPaneTotalWidth = dayPaneWidth + paneDividerWidth
    /// 予定の詳細の列の幅（3 列のとき）。
    static let detailColumnWidth: CGFloat = 360
    /// 詳細の列の左右の余白。
    static let detailColumnLeadingInset: CGFloat = 12
    static let detailColumnTrailingInset: CGFloat = 8
    /// 詳細の列と、その左の区切り線の幅の合計。
    static let detailColumnTotalWidth = detailColumnWidth + paneDividerWidth
    /// 画面に余裕があるときのマス目の幅（左右の余白を含む）。目標の幅である。
    static let targetGridWidth: CGFloat = 1120
    /// 画面が小さくてもマス目に残す幅（左右の余白を含む）。
    static let minimumGridWidth: CGFloat = 720

    /// 画面に余裕があるときの大きさ（3 列）。高さは、週の行が 162pt になり、1 マスに予定の行が 8 行入る値。
    static let targetSize = CGSize(width: targetGridWidth + dayPaneTotalWidth + detailColumnTotalWidth, height: 1100)
    /// 画面が小さくても下回らせない大きさ（2 列）。
    static let minimumSize = CGSize(width: minimumGridWidth + dayPaneTotalWidth, height: 520)
    /// 3 列で出せる幅の下限。マス目の下限に、日の欄と詳細の列を足した値。
    static let threeColumnMinimumWidth = minimumGridWidth + dayPaneTotalWidth + detailColumnTotalWidth
    /// 可視領域の端から空ける余白。左右と上下のそれぞれに取る。
    static let screenMargin: CGFloat = 24

    /// ポップオーバーの内容の外側の余白。
    static let contentPadding: CGFloat = 12
    /// 見出し、曜日の行、フッターの高さ。マス目に使える高さを決めるため、内容に依らず固定にする。
    static let headerHeight: CGFloat = 28
    static let weekdayRowHeight: CGFloat = 20
    static let footerHeight: CGFloat = 28
    /// マス目とフッターの間の区切り線。
    static let dividerHeight: CGFloat = 1
    /// マス目の上下に積む、見出し、曜日の行、区切り線、フッターの間隔。
    static let sectionSpacing: CGFloat = 6

    /// 見えている週の数。
    static let visibleWeekCount = WeekTimeline.visibleWeekCount

    /// 列の構成。余白を引いた可視領域の幅が 3 列の下限以上なら 3 列、それより狭ければ 2 列。
    static func layout(visibleFrame: CGRect) -> PaneLayout {
        visibleFrame.width - 2 * screenMargin >= threeColumnMinimumWidth ? .threeColumn : .twoColumn
    }

    /// 余白を引いた可視領域に収め、下限を下回らせない大きさ。
    static func size(visibleFrame: CGRect) -> CGSize {
        let availableWidth = visibleFrame.width - 2 * screenMargin
        let width = switch layout(visibleFrame: visibleFrame) {
        case .threeColumn: min(targetSize.width, availableWidth)
        case .twoColumn: max(minimumSize.width, availableWidth)
        }
        return CGSize(width: width, height: max(minimumSize.height, min(targetSize.height, visibleFrame.height - 2 * screenMargin)))
    }

    /// マス目を含む左の列の幅（余白を除く）。ポップオーバーの幅から、左右の余白、日の欄、詳細の列（3 列のとき）、区切り線を引いた値。
    static func gridWidth(popoverWidth: CGFloat, layout: PaneLayout) -> CGFloat {
        let detail: CGFloat = layout == .threeColumn ? detailColumnTotalWidth : 0
        return popoverWidth - 2 * contentPadding - dayPaneTotalWidth - detail
    }

    /// 見出し、曜日の行、フッターと、それらの間隔を除いた、マス目に使える高さ。
    static func gridHeight(popoverHeight: CGFloat) -> CGFloat {
        let chrome = 2 * contentPadding + headerHeight + weekdayRowHeight + dividerHeight + footerHeight + 4 * sectionSpacing
        return popoverHeight - chrome
    }

    /// 週の行の高さ。マス目に使える高さを見えている週の数で割り、小数を切り捨てる。
    static func rowHeight(popoverHeight: CGFloat) -> CGFloat {
        (gridHeight(popoverHeight: popoverHeight) / CGFloat(visibleWeekCount)).rounded(.down)
    }
}
