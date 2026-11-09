import Testing
@testable import BarlunariDomain

@Suite struct WeekdayTests {
    @Test func 値は暦のfirstWeekdayと同じで日曜が1土曜が7() {
        #expect(Weekday.sunday.rawValue == 1)
        #expect(Weekday.monday.rawValue == 2)
        #expect(Weekday.saturday.rawValue == 7)
        #expect(Weekday.allCases.map(\.rawValue) == Array(1...7))
    }

    @Test(arguments: 1...7) func 暦の値から曜日を作れる(value: Int) throws {
        #expect(try Weekday(calendarValue: value).rawValue == value)
    }

    @Test(arguments: [0, 8, -1, 100]) func 範囲外の値は不正な曜日として投げる(value: Int) {
        #expect(throws: DomainError.invalidWeekday(value)) { try Weekday(calendarValue: value) }
    }
}
