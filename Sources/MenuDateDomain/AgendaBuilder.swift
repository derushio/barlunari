import Foundation

/// 予定の一覧から、日ごとの予定表を作るドメインサービス。
public struct AgendaBuilder: Sendable {
    public init() {}

    /// - Parameters:
    ///   - visibleCalendars: 表示するカレンダー。これに含まれないカレンダーの予定は除く。
    ///   - accountOrder: アカウントの並び順。同じ予定が複数のアカウントから来たとき、先のアカウントの予定を残す。
    ///     含まれないアカウントは最後に回し、その中は `AccountID` の順にする。
    ///   - range: 返す日の範囲。予定のない日も `DayAgenda` を返す。
    ///
    /// 祝日カレンダーや招待された会議は、複数のアカウントのカレンダーに別々に現れ、iCalendar の UID と日時が同じになる。
    /// UID と日時が同じ予定は 1 件にし、アカウントの並び順で先の予定を残す。同じアカウントの中では、入力で先の予定を残す。
    /// UID を持たない予定は同じ予定かどうか判定できないため、除去の対象にしない。
    /// 表示するカレンダーの絞り込みの後に除くので、先のアカウントのカレンダーを非表示にしていれば、後のアカウントの予定が残る。
    /// 辞退した予定の除外は重複の除去の後に行う。
    public func build(
        events: [CalendarEvent],
        visibleCalendars: Set<UserCalendar.Identity>,
        accountOrder: [AccountID],
        range: DayRange,
        calendar: Calendar
    ) -> [DayAgenda] {
        let candidates = Self.removingDuplicates(
            from: events.filter { visibleCalendars.contains($0.calendarIdentity) },
            accountOrder: accountOrder
        ).filter { $0.attendance != .declined }
        let days = range.days(calendar: calendar)
        // 夏時間の日は 24 時間とは限らないため、各日の終端は翌日の 0:00 から求める。
        let boundaries = days.map { $0.startDate(in: calendar) } + [range.end.startDate(in: calendar)]

        return days.enumerated().map { index, day in
            let dayInterval = (start: boundaries[index], end: boundaries[index + 1])
            let onDay = candidates.filter { Self.occurs($0.schedule, on: day, dayInterval: dayInterval) }
            return DayAgenda(day: day, events: onDay.sorted(by: Self.isOrderedBefore))
        }
    }

    /// 日ごとの、予定があるカレンダーの色。重複は除き、その日の予定の並び順で最初に現れた順に並べる。
    ///
    /// `calendars` にないカレンダーの予定は色を持たないので数えない。予定のない日はキーを持たない。
    public func colorsByDay(of days: [DayAgenda], calendars: [UserCalendar]) -> [CalendarDay: [CalendarColor]] {
        let colorByCalendar = Dictionary(calendars.map { ($0.id, $0.color) }, uniquingKeysWith: { first, _ in first })
        var result: [CalendarDay: [CalendarColor]] = [:]
        for agenda in days {
            var colors: [CalendarColor] = []
            for event in agenda.events {
                if let color = colorByCalendar[event.calendarIdentity], !colors.contains(color) {
                    colors.append(color)
                }
            }
            if !colors.isEmpty { result[agenda.day] = colors }
        }
        return result
    }

    private static func removingDuplicates(from events: [CalendarEvent], accountOrder: [AccountID]) -> [CalendarEvent] {
        var rank: [AccountID: Int] = [:]
        for (index, id) in accountOrder.enumerated() where rank[id] == nil { rank[id] = index }
        func precedes(_ lhs: AccountID, _ rhs: AccountID) -> Bool {
            switch (rank[lhs], rank[rhs]) {
            case (let l?, let r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs < rhs
            }
        }
        var kept: [CalendarEvent.SharedKey: CalendarEvent] = [:]
        var unkeyed: [CalendarEvent] = []
        for event in events {
            guard let key = event.sharedKey else {
                unkeyed.append(event)
                continue
            }
            // 同じアカウントの予定は、先に入力されたものを残すため、置き換えない。
            if let existing = kept[key], !precedes(event.accountID, existing.accountID) { continue }
            kept[key] = event
        }
        return unkeyed + Array(kept.values)
    }

    private static func occurs(
        _ schedule: EventSchedule,
        on day: CalendarDay,
        dayInterval: (start: Date, end: Date)
    ) -> Bool {
        switch schedule {
        case .allDay(let range):
            return range.contains(day)
        case .timed(let interval):
            guard interval.start < dayInterval.end else { return false }
            // 終了がその日の 0:00 ちょうどの予定は前日で終わっているので入れない。
            // 長さ 0 の予定だけは、開始日に入れる。
            if interval.end > dayInterval.start { return true }
            return interval.duration == 0 && interval.start >= dayInterval.start
        }
    }

    private static func isOrderedBefore(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        switch (lhs.schedule, rhs.schedule) {
        case (.allDay, .timed): return true
        case (.timed, .allDay): return false
        case (.timed(let l), .timed(let r)) where l.start != r.start:
            return l.start < r.start
        default:
            break
        }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        // 完全に同じ並びの入力でも結果が変わらないよう、最後は ID で決める。
        return (lhs.calendarID, lhs.eventID, lhs.accountID) < (rhs.calendarID, rhs.eventID, rhs.accountID)
    }
}
