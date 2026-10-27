import Foundation

/// タイムゾーンを持たない日付。終日予定や表示範囲の単位に使う。
///
/// 西暦（グレゴリオ暦）を前提とする。`Calendar` を受け取る API には、グレゴリオ暦の `Calendar` を渡すこと。
public struct CalendarDay: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// 受け付ける西暦年。`Date` との往復で破綻しない範囲に絞る。
    public static let supportedYears = 1...9999

    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        guard Self.supportedYears.contains(year),
              (1...12).contains(month),
              day >= 1,
              day <= Self.daysInMonth(year: year, month: month)
        else {
            throw DomainError.invalidDay(year: year, month: month, day: day)
        }
        self.init(uncheckedYear: year, month: month, day: day)
    }

    /// 呼び出し側が妥当性を保証する場合だけ使う。
    init(uncheckedYear year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// `calendar` のタイムゾーンで `date` が属する日を返す。
    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            preconditionFailure("Calendar が年月日を返さなかった")
        }
        self.init(uncheckedYear: year, month: month, day: day)
    }

    /// `calendar` のタイムゾーンにおけるその日の 0:00。夏時間で 0:00 が存在しない日は実在する最初の時刻になる。
    public func startDate(in calendar: Calendar) -> Date {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            preconditionFailure("妥当な CalendarDay から Date を作れなかった")
        }
        return calendar.startOfDay(for: date)
    }

    public func adding(days: Int, calendar: Calendar) -> CalendarDay {
        guard let moved = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar)) else {
            preconditionFailure("日数の加算に失敗した")
        }
        return CalendarDay(date: moved, calendar: calendar)
    }

    public var calendarMonth: CalendarMonth { CalendarMonth(uncheckedYear: year, month: month) }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}
