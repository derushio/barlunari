import Testing
@testable import BarlunariDomain

@Suite struct WeekdayTests {
    @Test func 値は暦のfirstWeekdayと同じで日曜が1土曜が7() {
        #expect(Weekday.sunday.rawValue == 1)
        #expect(Weekday.monday.rawValue == 2)
        #expect(Weekday.saturday.rawValue == 7)
        #expect(Weekday.allCases.map(\.rawValue) == Array(1...7))
    }

    @Test(arguments: [0, 8, -1]) func 範囲外の値からは曜日を作らない(value: Int) {
        #expect(Weekday(rawValue: value) == nil)
    }
}
