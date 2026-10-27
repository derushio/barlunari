import Foundation

/// `CalendarDay` の半開区間 `[start, end)`。空の区間は表現できない。
public struct DayRange: Sendable, Hashable {
    public let start: CalendarDay
    public let end: CalendarDay

    public init(start: CalendarDay, end: CalendarDay) throws {
        guard start < end else { throw DomainError.emptyDayRange }
        self.start = start
        self.end = end
    }

    public init(start: CalendarDay, dayCount: Int, calendar: Calendar) throws {
        guard dayCount > 0 else { throw DomainError.emptyDayRange }
        try self.init(start: start, end: start.adding(days: dayCount, calendar: calendar))
    }

    public func contains(_ day: CalendarDay) -> Bool {
        start <= day && day < end
    }

    public func overlaps(_ other: DayRange) -> Bool {
        start < other.end && other.start < end
    }

    public func days(calendar: Calendar) -> [CalendarDay] {
        var result: [CalendarDay] = []
        var current = start
        while current < end {
            result.append(current)
            current = current.adding(days: 1, calendar: calendar)
        }
        return result
    }

    public func dateInterval(calendar: Calendar) -> DateInterval {
        DateInterval(start: start.startDate(in: calendar), end: end.startDate(in: calendar))
    }
}
