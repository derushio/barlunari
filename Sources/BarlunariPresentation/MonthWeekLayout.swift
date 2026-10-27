import Foundation
import BarlunariDomain

/// 月表示の 1 週 7 日分の予定を、マスの中の行（lane）に割り当てた結果。
///
/// 週をまたぐ予定と終日予定は、列をまたぐ 1 本のバーにする。1 日に収まる時刻付きの予定は、その日の列だけを占める。
/// 同じ予定は、週の中で複数の日に入っていても 1 つの `Item` にする。
public struct MonthWeekLayout: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public enum Kind: Equatable, Sendable {
            /// 列をまたぐバー。前の週から続くか、次の週へ続くときは、その側の端を切って描く。
            case bar(continuesFromPreviousWeek: Bool, continuesToNextWeek: Bool)
            /// 1 日に収まる時刻付きの予定。`timeText` は開始時刻。
            case timed(timeText: String)
        }

        public let id: CalendarEvent.Identity
        /// 予定がかかる列。`0..<7` の中にある。
        public let columns: Range<Int>
        /// 列の中で上から数えた行の番号。
        public let lane: Int
        public let kind: Kind
        /// タイトルがなければ「(タイトルなし)」。
        public let title: String
        public let color: CalendarColor?
        public let isPast: Bool
    }

    /// 表示するときに残した予定と、列ごとの隠れた件数。
    public struct Visible: Equatable, Sendable {
        public let items: [Item]
        /// 列ごとの、その列にかかる隠した予定の数。7 要素である。
        public let hiddenCountByColumn: [Int]
    }

    /// 全予定。バーを先に、その後に 1 日の予定を日の順に並べる。
    public let items: [Item]

    static let columnCount = 7

    /// - Parameters:
    ///   - days: 週の 7 日。
    ///   - eventsByDay: 日ごとの予定。日の中の並び順は `AgendaBuilder` の並び順である。
    ///   - color: 予定のカレンダーの色。
    init(
        days: [CalendarDay],
        eventsByDay: [CalendarDay: [CalendarEvent]],
        color: (CalendarEvent) -> CalendarColor?,
        now: Date,
        calendar: Calendar,
        formatter: CalendarFormatter
    ) {
        precondition(days.count == Self.columnCount, "週は 7 日である")

        // 予定ごとに、かかる列を集める。入力の順（日の順、日の中の並び順）を、同順位のときの順序に使う。
        var order: [CalendarEvent.Identity] = []
        var occurrences: [CalendarEvent.Identity: (event: CalendarEvent, columns: Range<Int>)] = [:]
        for (column, day) in days.enumerated() {
            for event in eventsByDay[day] ?? [] {
                if let existing = occurrences[event.id] {
                    occurrences[event.id] = (existing.event, existing.columns.lowerBound..<(column + 1))
                } else {
                    order.append(event.id)
                    occurrences[event.id] = (event, column..<(column + 1))
                }
            }
        }

        var bars: [Pending] = []
        var singles: [Pending] = []
        for id in order {
            guard let (event, columns) = occurrences[id] else { continue }
            let kind = Self.kind(of: event, columns: columns, days: days, calendar: calendar, formatter: formatter)
            let lastDay = days[columns.upperBound - 1]
            let pending = Pending(
                event: event, columns: columns, kind: kind, lane: 0,
                isPast: event.schedule.hasEnded(on: lastDay, at: now, calendar: calendar)
            )
            if case .bar = kind { bars.append(pending) } else { singles.append(pending) }
        }
        // 開始の早い順、同じなら長い順、同じなら入力の順。`sorted` は安定でないため、入力の順を明示する。
        let barOrder = Dictionary(uniqueKeysWithValues: bars.enumerated().map { ($1.event.id, $0) })
        bars.sort { lhs, rhs in
            if lhs.columns.lowerBound != rhs.columns.lowerBound { return lhs.columns.lowerBound < rhs.columns.lowerBound }
            if lhs.columns.count != rhs.columns.count { return lhs.columns.count > rhs.columns.count }
            return barOrder[lhs.event.id, default: 0] < barOrder[rhs.event.id, default: 0]
        }

        // occupied[lane] は、その行で埋まっている列。
        var occupied: [[Bool]] = []
        func place(_ pending: inout Pending) {
            var lane = 0
            while true {
                if lane == occupied.count { occupied.append(Array(repeating: false, count: Self.columnCount)) }
                if pending.columns.allSatisfy({ !occupied[lane][$0] }) { break }
                lane += 1
            }
            pending.lane = lane
            for column in pending.columns { occupied[lane][column] = true }
        }
        for index in bars.indices { place(&bars[index]) }
        // 1 日の予定は、日ごとにその日の並び順で置く。`singles` は日の順、日の中の並び順に並んでいる。
        for index in singles.indices { place(&singles[index]) }

        items = (bars + singles).map { pending in
            Item(
                id: pending.event.id,
                columns: pending.columns,
                lane: pending.lane,
                kind: pending.kind,
                title: pending.event.title.isEmpty ? "(タイトルなし)" : pending.event.title,
                color: color(pending.event),
                isPast: pending.isPast
            )
        }
    }

    /// 表示できる行の数に収まる予定と、収まらない予定の件数を返す。
    ///
    /// 行が `laneCapacity` 以上の予定は隠す。隠した予定がかかる列では、最後の行（`laneCapacity - 1`）を「他 N 件」の行に使うので、
    /// その列にかかる最後の行の予定も隠す。隠したバーがかかる別の列にも同じ規則が当てはまるため、変化がなくなるまで繰り返す。
    /// `laneCapacity` が 0 以下なら、すべて隠す。
    public func visible(laneCapacity: Int) -> Visible {
        guard laneCapacity > 0 else {
            return Visible(items: [], hiddenCountByColumn: hiddenCounts(of: items))
        }
        var isHidden = items.map { $0.lane >= laneCapacity }
        var changed = true
        while changed {
            changed = false
            var hasHidden = Array(repeating: false, count: Self.columnCount)
            for (index, item) in items.enumerated() where isHidden[index] {
                for column in item.columns { hasHidden[column] = true }
            }
            for (index, item) in items.enumerated() where !isHidden[index] && item.lane == laneCapacity - 1 {
                if item.columns.contains(where: { hasHidden[$0] }) {
                    isHidden[index] = true
                    changed = true
                }
            }
        }
        let shown = items.indices.filter { !isHidden[$0] }.map { items[$0] }
        let hidden = items.indices.filter { isHidden[$0] }.map { items[$0] }
        return Visible(items: shown, hiddenCountByColumn: hiddenCounts(of: hidden))
    }

    private func hiddenCounts(of hidden: [Item]) -> [Int] {
        var counts = Array(repeating: 0, count: Self.columnCount)
        for item in hidden {
            for column in item.columns { counts[column] += 1 }
        }
        return counts
    }

    private struct Pending {
        let event: CalendarEvent
        let columns: Range<Int>
        let kind: Item.Kind
        var lane: Int
        let isPast: Bool
    }

    /// 終日予定と、日をまたぐ時刻付きの予定はバー、1 日に収まる時刻付きの予定は時刻付きの行にする。
    private static func kind(
        of event: CalendarEvent, columns: Range<Int>, days: [CalendarDay], calendar: Calendar, formatter: CalendarFormatter
    ) -> Item.Kind {
        switch event.schedule {
        case .allDay(let range):
            let firstDay = days[columns.lowerBound]
            let lastDay = days[columns.upperBound - 1]
            return .bar(
                continuesFromPreviousWeek: range.start < firstDay,
                continuesToNextWeek: lastDay.adding(days: 1, calendar: calendar) < range.end
            )
        case .timed:
            let first = event.schedule.span(on: days[columns.lowerBound], calendar: calendar)
            let last = event.schedule.span(on: days[columns.upperBound - 1], calendar: calendar)
            switch (first, last) {
            case (.withinDay(let start, _), .withinDay):
                return .timed(timeText: formatter.time(start))
            default:
                let fromPrevious: Bool = switch first {
                case .entireDay, .endsOnDay: true
                default: false
                }
                let toNext: Bool = switch last {
                case .entireDay, .startsOnDay: true
                default: false
                }
                return .bar(continuesFromPreviousWeek: fromPrevious, continuesToNextWeek: toNext)
            }
        }
    }
}
