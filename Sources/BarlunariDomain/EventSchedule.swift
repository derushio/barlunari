import Foundation

public enum EventSchedule: Sendable, Hashable {
    /// 終了日は排他的である。1 日だけの予定は `[当日, 翌日)` になる。
    case allDay(DayRange)
    case timed(DateInterval)

    /// ある日に予定がどう収まるか。日をまたぐ予定は、その日に収まらない側を持たない。
    public enum DaySpan: Sendable, Hashable {
        /// 終日予定。
        case allDay
        /// 時刻付きで、前日から続き翌日へ続く。その日は丸ごと埋まる。
        case entireDay
        /// 時刻付きで、前日から続き、その日の `end` に終わる。
        case endsOnDay(end: Date)
        /// 時刻付きで、その日の `start` に始まり、翌日へ続く。
        case startsOnDay(start: Date)
        /// 時刻付きで、その日に収まる。
        case withinDay(start: Date, end: Date)
    }

    public var isAllDay: Bool {
        if case .allDay = self { true } else { false }
    }

    /// `day` の表示において、予定が終わっているか。
    ///
    /// 終日予定は `now` の日より前の日なら終わっている。時刻付きの予定は終了時刻が `now` 以前なら終わっている。
    public func hasEnded(on day: CalendarDay, at now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .allDay:
            day < CalendarDay(date: now, calendar: calendar)
        case .timed(let interval):
            interval.end <= now
        }
    }

    /// `day` に対して予定の開始と終了がはみ出しているかを返す。
    ///
    /// 夏時間の日は 24 時間とは限らないため、日の終端は翌日の 0:00 から求める。
    public func span(on day: CalendarDay, calendar: Calendar) -> DaySpan {
        guard case .timed(let interval) = self else { return .allDay }
        let dayStart = day.startDate(in: calendar)
        let dayEnd = day.adding(days: 1, calendar: calendar).startDate(in: calendar)
        switch (interval.start < dayStart, interval.end > dayEnd) {
        case (true, true): return .entireDay
        case (true, false): return .endsOnDay(end: interval.end)
        case (false, true): return .startsOnDay(start: interval.start)
        case (false, false): return .withinDay(start: interval.start, end: interval.end)
        }
    }
}
