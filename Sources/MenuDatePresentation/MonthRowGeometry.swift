import CoreGraphics
import MenuDateDomain

/// 月表示の 1 週の行の寸法と、クリックの位置の判定。描画とクリックの判定が同じ計算を使うよう、ここに集める。SwiftUI に依存しない。
///
/// 行は 7 つの列に等分する。各マスは、上に日の数字の領域（`dayHeaderHeight`）、その下に予定の行（lane）を `laneHeight` ずつ積む。
struct MonthRowGeometry: Equatable {
    /// クリックされた場所の意味。
    enum Target: Equatable {
        /// 日のマス（予定のない場所）。値は列。
        case day(Int)
        case event(CalendarEvent.Identity)
        /// 「他 N 件」。値は列。
        case more(Int)
    }

    static let columnCount = 7
    /// マスの上の、日の数字の領域の高さ。
    static let dayHeaderHeight: CGFloat = 24
    /// 予定の 1 行の高さ。
    static let laneHeight: CGFloat = 17
    /// マスの下の余白。
    static let bottomInset: CGFloat = 2
    /// バーと予定の行の、マスの左右の端からの余白。
    static let horizontalInset: CGFloat = 2

    /// 行の大きさ。
    let size: CGSize

    var cellWidth: CGFloat { size.width / CGFloat(Self.columnCount) }

    var laneCapacity: Int { Self.laneCapacity(rowHeight: size.height) }

    /// 行の高さに入る予定の行の数。
    static func laneCapacity(rowHeight: CGFloat) -> Int {
        max(0, Int(((rowHeight - dayHeaderHeight - bottomInset) / laneHeight).rounded(.down)))
    }

    /// 列のマスの枠。
    func cellRect(column: Int) -> CGRect {
        CGRect(x: CGFloat(column) * cellWidth, y: 0, width: cellWidth, height: size.height)
    }

    /// 予定の行 `lane` の、`columns` にまたがる枠。左右に `horizontalInset` を空ける。
    func laneRect(lane: Int, columns: Range<Int>) -> CGRect {
        CGRect(
            x: CGFloat(columns.lowerBound) * cellWidth + Self.horizontalInset,
            y: Self.dayHeaderHeight + CGFloat(lane) * Self.laneHeight,
            width: CGFloat(columns.count) * cellWidth - 2 * Self.horizontalInset,
            height: Self.laneHeight
        )
    }

    /// 位置の列。行の外の位置は端の列に寄せる。
    func column(at x: CGFloat) -> Int {
        guard cellWidth > 0 else { return 0 }
        return min(max(Int((x / cellWidth).rounded(.down)), 0), Self.columnCount - 1)
    }

    /// クリックされた位置の意味。予定、「他 N 件」、それ以外の順に調べる。
    func target(at point: CGPoint, visible: MonthWeekLayout.Visible) -> Target {
        let column = column(at: point.x)
        let laneOffset = point.y - Self.dayHeaderHeight
        guard laneOffset >= 0 else { return .day(column) }
        let lane = Int((laneOffset / Self.laneHeight).rounded(.down))
        guard lane < laneCapacity else { return .day(column) }
        if let item = visible.items.first(where: { $0.lane == lane && $0.columns.contains(column) }) {
            return .event(item.id)
        }
        if lane == laneCapacity - 1, visible.hiddenCountByColumn.indices.contains(column), visible.hiddenCountByColumn[column] > 0 {
            return .more(column)
        }
        return .day(column)
    }
}
