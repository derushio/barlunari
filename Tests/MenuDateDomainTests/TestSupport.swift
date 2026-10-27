import Foundation
@testable import MenuDateDomain

/// テストはタイムゾーンを固定し、実行環境の設定に依存させない。
enum TestSupport {
    static func calendar(_ identifier: String = "Asia/Tokyo") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        try! CalendarDay(year: year, month: month, day: day)
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
        calendar: Calendar = TestSupport.calendar()
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func range(_ start: CalendarDay, days: Int, calendar: Calendar = TestSupport.calendar()) -> DayRange {
        try! DayRange(start: start, dayCount: days, calendar: calendar)
    }

    static func accountID(_ value: String) -> AccountID { try! AccountID(value) }
    static func calendarID(_ value: String) -> CalendarID { try! CalendarID(value) }
    static func eventID(_ value: String) -> EventID { try! EventID(value) }
}
