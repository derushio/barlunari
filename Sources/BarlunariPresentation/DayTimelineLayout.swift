import Foundation

/// 日の欄の時間軸に置く予定のブロックの配置。SwiftUI にも暦にも依存しない純粋な値である。
///
/// 予定は、その日の 0 時からの分（0〜1440）で表す。日をまたぐ予定は、呼び出し側が 0 か 1440 で切って渡す。
///
/// - 位置は開始時刻で決める。短い予定が読めるよう、表示上の長さに下限（`minimumDisplayMinutes`）を持たせる。
///   下限を持たせた終了（`displayEndMinute`）は、ブロックの高さと重なりの判定に使い、開始の位置は動かさない
/// - 開始の早い順、同じなら長い順、同じなら入力の順に並べ、空いている最初の列へ入れる
/// - 推移的に重なる予定のまとまり（クラスター）ごとに、列の数を数え、そのまとまりの予定の幅を列数で等分する
struct DayTimelineLayout<ID: Hashable & Sendable>: Equatable, Sendable {
    /// 配置する予定 1 件。
    struct Entry: Equatable, Sendable {
        let id: ID
        /// 0 時からの分。
        let startMinute: Int
        /// 0 時からの分。開始より前なら開始と同じとみなす。
        let endMinute: Int

        init(id: ID, startMinute: Int, endMinute: Int) {
            self.id = id
            self.startMinute = startMinute
            self.endMinute = endMinute
        }
    }

    /// 配置したブロック 1 つ。
    struct Block: Equatable, Sendable {
        let id: ID
        let startMinute: Int
        /// 下限を持たせた終了。1440 を超えない。
        let displayEndMinute: Int
        /// 重なりのまとまりの中で、左から数えた列の番号。
        let column: Int
        /// 重なりのまとまりの列の数。幅は 1 / `columnCount` である。
        let columnCount: Int
    }

    static var minutesPerDay: Int { 1440 }
    /// 表示上の長さの下限（分）。1 時間 48pt のとき 24pt で、1 行のタイトルが読める。
    static var minimumDisplayMinutes: Int { 30 }

    /// 下限を持たせて範囲に収めた予定。
    private struct Item {
        let id: ID
        let start: Int
        let end: Int
        let index: Int
    }

    /// 並べた順のブロック。入力の順ではなく、開始の早い順である。
    let blocks: [Block]

    init(entries: [Entry], minimumDisplayMinutes: Int = Self.minimumDisplayMinutes) {
        let items = entries.enumerated().map { index, entry -> Item in
            let start = min(max(entry.startMinute, 0), Self.minutesPerDay - 1)
            let end = min(Self.minutesPerDay, max(entry.endMinute, start + minimumDisplayMinutes))
            return Item(id: entry.id, start: start, end: end, index: index)
        }
        let sorted = items.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end > rhs.end }
            return lhs.index < rhs.index
        }

        var result: [Block] = []
        var columnEnds: [Int] = []
        var assignments: [(item: Item, column: Int)] = []
        var clusterEnd = 0

        func closeCluster() {
            let count = max(columnEnds.count, 1)
            for assignment in assignments {
                result.append(Block(
                    id: assignment.item.id, startMinute: assignment.item.start, displayEndMinute: assignment.item.end,
                    column: assignment.column, columnCount: count
                ))
            }
            assignments.removeAll()
            columnEnds.removeAll()
        }

        for item in sorted {
            if !assignments.isEmpty, item.start >= clusterEnd { closeCluster() }
            if assignments.isEmpty { clusterEnd = item.end }
            let column = columnEnds.firstIndex { $0 <= item.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(item.end) } else { columnEnds[column] = item.end }
            assignments.append((item, column))
            clusterEnd = max(clusterEnd, item.end)
        }
        closeCluster()
        blocks = result
    }
}

/// 日の欄を開いたときの、時間軸のスクロール位置を決める規則。
enum DayScheduleScroll {
    /// 目安にする時刻の何分前を一番上にするか。
    static let leadMinutes = 60
    /// 時刻付きの予定がなく、今日でもないときの時刻（分）。朝 8 時。
    static let defaultMinute = 8 * 60
    /// 位置を揃える単位（分）。
    static let slotMinutes = 30

    /// 一番上にする時刻（0 時からの分）。`slotMinutes` の単位に切り捨てる。
    ///
    /// 今日なら現在時刻の `leadMinutes` 前、そうでなければ最初の時刻付きの予定の開始の `leadMinutes` 前、時刻付きの予定がなければ 8 時。
    /// - Parameters:
    ///   - currentMinute: 今日のときの現在時刻。今日でなければ `nil`。
    ///   - firstTimedStartMinute: その日の最初の時刻付きの予定の開始。なければ `nil`。
    static func targetMinute(currentMinute: Int?, firstTimedStartMinute: Int?) -> Int {
        let base: Int
        if let currentMinute {
            base = currentMinute - leadMinutes
        } else if let firstTimedStartMinute {
            base = firstTimedStartMinute - leadMinutes
        } else {
            base = defaultMinute
        }
        return max(0, base) / slotMinutes * slotMinutes
    }
}
