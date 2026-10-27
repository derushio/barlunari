import Foundation
import Testing
@testable import MenuDateDomain

@Suite struct CalendarDayTests {
    @Test(arguments: [
        (2026, 0, 1), (2026, 13, 1), (2026, 1, 0), (2026, 1, 32),
        (2026, 4, 31), (2026, 2, 29), (1900, 2, 29), (0, 1, 1), (10000, 1, 1),
    ])
    func rejectsInvalidDates(year: Int, month: Int, day: Int) {
        #expect(throws: DomainError.invalidDay(year: year, month: month, day: day)) {
            try CalendarDay(year: year, month: month, day: day)
        }
    }

    @Test(arguments: [(2024, 2, 29), (2000, 2, 29), (2026, 12, 31), (1, 1, 1), (9999, 12, 31)])
    func acceptsValidDates(year: Int, month: Int, day: Int) throws {
        let value = try CalendarDay(year: year, month: month, day: day)
        #expect(value.year == year && value.month == month && value.day == day)
    }

    @Test func comparesChronologically() {
        let a = TestSupport.day(2026, 1, 31)
        let b = TestSupport.day(2026, 2, 1)
        let c = TestSupport.day(2027, 1, 1)
        #expect(a < b && b < c)
        #expect([c, a, b].sorted() == [a, b, c])
    }

    @Test func derivesFromDateInCalendarTimeZone() {
        // UTC の 10/24 16:00 は東京では 10/25 01:00
        let instant = TestSupport.date(2026, 10, 24, 16, 0, calendar: TestSupport.calendar("UTC"))
        #expect(CalendarDay(date: instant, calendar: TestSupport.calendar("UTC")) == TestSupport.day(2026, 10, 24))
        #expect(CalendarDay(date: instant, calendar: TestSupport.calendar("Asia/Tokyo")) == TestSupport.day(2026, 10, 25))
    }

    @Test func startDateIsMidnightInGivenTimeZone() {
        let day = TestSupport.day(2026, 10, 24)
        #expect(day.startDate(in: TestSupport.calendar()) == TestSupport.date(2026, 10, 24))
        #expect(day.startDate(in: TestSupport.calendar("UTC")) != day.startDate(in: TestSupport.calendar()))
    }

    @Test func addsDaysAcrossMonthAndYear() {
        let calendar = TestSupport.calendar()
        #expect(TestSupport.day(2026, 12, 31).adding(days: 1, calendar: calendar) == TestSupport.day(2027, 1, 1))
        #expect(TestSupport.day(2026, 3, 1).adding(days: -1, calendar: calendar) == TestSupport.day(2026, 2, 28))
        #expect(TestSupport.day(2024, 2, 28).adding(days: 1, calendar: calendar) == TestSupport.day(2024, 2, 29))
    }

    @Test func addsDaysAcrossDaylightSavingTransition() {
        let calendar = TestSupport.calendar("America/New_York")
        // 2026-03-08 は夏時間の開始日（23 時間の日）
        #expect(TestSupport.day(2026, 3, 8).adding(days: 1, calendar: calendar) == TestSupport.day(2026, 3, 9))
        #expect(TestSupport.day(2026, 11, 1).adding(days: 1, calendar: calendar) == TestSupport.day(2026, 11, 2))
    }
}

@Suite struct CalendarMonthTests {
    @Test func rejectsInvalidMonth() {
        #expect(throws: DomainError.invalidMonth(year: 2026, month: 13)) { try CalendarMonth(year: 2026, month: 13) }
        #expect(throws: DomainError.invalidMonth(year: 2026, month: 0)) { try CalendarMonth(year: 2026, month: 0) }
    }

    @Test func movesAcrossYearBoundary() throws {
        let december = try CalendarMonth(year: 2026, month: 12)
        let january = try CalendarMonth(year: 2027, month: 1)
        #expect(december.next == january)
        #expect(january.previous == december)
    }

    @Test func staysAtSupportedBounds() throws {
        let first = try CalendarMonth(year: 1, month: 1)
        let last = try CalendarMonth(year: 9999, month: 12)
        #expect(first.previous == first)
        #expect(last.next == last)
    }

    @Test func providesFirstDayAndContainment() throws {
        let month = try CalendarMonth(year: 2026, month: 2)
        #expect(month.firstDay == TestSupport.day(2026, 2, 1))
        #expect(month.dayCount == 28)
        #expect(month.contains(TestSupport.day(2026, 2, 28)))
        #expect(!month.contains(TestSupport.day(2026, 3, 1)))
        #expect(!month.contains(TestSupport.day(2025, 2, 1)))
        #expect(CalendarMonth(containing: TestSupport.day(2026, 2, 14)) == month)
    }

    @Test func comparesChronologically() throws {
        #expect(try CalendarMonth(year: 2026, month: 12) < CalendarMonth(year: 2027, month: 1))
    }
}

@Suite struct DayRangeTests {
    let calendar = TestSupport.calendar()

    @Test func rejectsEmptyOrReversedRange() {
        let day = TestSupport.day(2026, 10, 24)
        #expect(throws: DomainError.emptyDayRange) { try DayRange(start: day, end: day) }
        #expect(throws: DomainError.emptyDayRange) { try DayRange(start: day, end: TestSupport.day(2026, 10, 23)) }
        #expect(throws: DomainError.emptyDayRange) { try DayRange(start: day, dayCount: 0, calendar: calendar) }
    }

    @Test func listsDaysAsHalfOpenInterval() {
        let range = TestSupport.range(TestSupport.day(2026, 12, 30), days: 4, calendar: calendar)
        #expect(range.days(calendar: calendar) == [
            TestSupport.day(2026, 12, 30), TestSupport.day(2026, 12, 31),
            TestSupport.day(2027, 1, 1), TestSupport.day(2027, 1, 2),
        ])
        #expect(range.end == TestSupport.day(2027, 1, 3))
        #expect(range.contains(TestSupport.day(2027, 1, 2)))
        #expect(!range.contains(TestSupport.day(2027, 1, 3)))
    }

    @Test func overlapsOnlyWhenSharingDays() {
        let a = TestSupport.range(TestSupport.day(2026, 10, 1), days: 3, calendar: calendar)
        let touching = TestSupport.range(TestSupport.day(2026, 10, 4), days: 2, calendar: calendar)
        let overlapping = TestSupport.range(TestSupport.day(2026, 10, 3), days: 2, calendar: calendar)
        #expect(!a.overlaps(touching))
        #expect(!touching.overlaps(a))
        #expect(a.overlaps(overlapping))
        #expect(overlapping.overlaps(a))
    }

    @Test func producesDateInterval() {
        let range = TestSupport.range(TestSupport.day(2026, 10, 24), days: 7, calendar: calendar)
        let interval = range.dateInterval(calendar: calendar)
        #expect(interval.start == TestSupport.date(2026, 10, 24))
        #expect(interval.end == TestSupport.date(2026, 10, 31))
    }
}
