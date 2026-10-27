/// 年と月。
public struct CalendarMonth: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) throws {
        guard CalendarDay.supportedYears.contains(year), (1...12).contains(month) else {
            throw DomainError.invalidMonth(year: year, month: month)
        }
        self.init(uncheckedYear: year, month: month)
    }

    init(uncheckedYear year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(containing day: CalendarDay) {
        self.init(uncheckedYear: day.year, month: day.month)
    }

    /// 対応年の端（1 年 1 月・9999 年 12 月）を越える場合は自分自身を返す。
    public var next: CalendarMonth {
        if month == 12 {
            return year == CalendarDay.supportedYears.upperBound ? self : CalendarMonth(uncheckedYear: year + 1, month: 1)
        }
        return CalendarMonth(uncheckedYear: year, month: month + 1)
    }

    /// 対応年の端を越える場合は自分自身を返す。
    public var previous: CalendarMonth {
        if month == 1 {
            return year == CalendarDay.supportedYears.lowerBound ? self : CalendarMonth(uncheckedYear: year - 1, month: 12)
        }
        return CalendarMonth(uncheckedYear: year, month: month - 1)
    }

    public var firstDay: CalendarDay {
        CalendarDay(uncheckedYear: year, month: month, day: 1)
    }

    public var dayCount: Int {
        CalendarDay.daysInMonth(year: year, month: month)
    }

    public func contains(_ day: CalendarDay) -> Bool {
        day.year == year && day.month == month
    }

    public static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public var description: String {
        "\(year)-\(month < 10 ? "0" : "")\(month)"
    }
}
