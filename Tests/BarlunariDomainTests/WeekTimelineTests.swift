import Foundation
import Testing
@testable import BarlunariDomain

@Suite struct WeekTimelineTests {
    let calendar = TestSupport.calendar()
    static let sunday = 1
    static let monday = 2
    /// 2026-10-24 は土曜日。
    let today = TestSupport.day(2026, 10, 24)

    func timeline(firstWeekday: Int = sunday, today: CalendarDay? = nil, weeksOnEachSide: Int = WeekTimeline.defaultWeeksOnEachSide) throws -> WeekTimeline {
        try WeekTimeline(today: today ?? self.today, firstWeekday: firstWeekday, weeksOnEachSide: weeksOnEachSide)
    }

    @Test func 今日を含む週の前後に1年分の週を並べる() throws {
        let timeline = try timeline()

        #expect(timeline.weekCount == 52 * 2 + 1)
        #expect(timeline.todayWeekIndex == 52)
        #expect(timeline.days(inWeek: 52) == (18...24).map { TestSupport.day(2026, 10, $0) })
        #expect(timeline.firstDay(ofWeek: 0) == TestSupport.day(2026, 10, 18).adding(days: -52 * 7, calendar: calendar))
    }

    @Test func 週の開始曜日に従って週の区切りが変わる() throws {
        let monday = try timeline(firstWeekday: Self.monday)

        #expect(monday.days(inWeek: monday.todayWeekIndex).first == TestSupport.day(2026, 10, 19))
        #expect(monday.days(inWeek: monday.todayWeekIndex).last == TestSupport.day(2026, 10, 25))
    }

    @Test func 週の開始曜日が範囲外なら生成できない() {
        #expect(throws: DomainError.invalidWeekday(0)) { try WeekTimeline(today: today, firstWeekday: 0) }
        #expect(throws: DomainError.invalidWeekday(8)) { try WeekTimeline(today: today, firstWeekday: 8) }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 7])
    func すべての週は開始曜日から始まり連続する(firstWeekday: Int) throws {
        let timeline = try timeline(firstWeekday: firstWeekday, weeksOnEachSide: 60)
        var previousLast: CalendarDay?
        for index in 0..<timeline.weekCount {
            let days = timeline.days(inWeek: index)
            #expect(days.count == 7)
            let weekday = calendar.component(.weekday, from: days[0].startDate(in: calendar))
            #expect(weekday == firstWeekday)
            if let previousLast { #expect(days[0] == previousLast.adding(days: 1, calendar: calendar)) }
            previousLast = days[6]
        }
    }

    @Test func 日数の変換はCalendarと一致する() throws {
        let samples = [
            TestSupport.day(1, 1, 1), TestSupport.day(1969, 12, 31), TestSupport.day(1970, 1, 1),
            TestSupport.day(2000, 2, 29), TestSupport.day(2026, 10, 24), TestSupport.day(2100, 3, 1),
            TestSupport.day(9999, 12, 31),
        ]
        for day in samples {
            #expect(CalendarDay(dayNumber: day.dayNumber) == day)
        }
        #expect(TestSupport.day(1970, 1, 1).dayNumber == 0)
        #expect(TestSupport.day(2026, 10, 25).dayNumber - TestSupport.day(2026, 10, 24).dayNumber == 1)
        #expect(TestSupport.day(2024, 3, 1).dayNumber - TestSupport.day(2024, 2, 28).dayNumber == 2)
    }

    @Test func 日を含む週の番号を返し並びの外はnilにする() throws {
        let timeline = try timeline()

        #expect(timeline.weekIndex(containing: today) == 52)
        #expect(timeline.weekIndex(containing: TestSupport.day(2026, 10, 18)) == 52)
        #expect(timeline.weekIndex(containing: TestSupport.day(2026, 10, 17)) == 51)
        #expect(timeline.weekIndex(containing: TestSupport.day(2026, 10, 25)) == 53)
        #expect(timeline.weekIndex(containing: TestSupport.day(1990, 1, 1)) == nil)
        #expect(timeline.weekIndex(containing: TestSupport.day(2040, 1, 1)) == nil)
    }

    @Test func 月の最初の週は1日を含む週で表示月に戻せる() throws {
        let timeline = try timeline()
        let october = try CalendarMonth(year: 2026, month: 10)

        // 10/1 は木曜日。日曜始まりの最初の週は 9/27 始まりで、今日の週の 3 週前。
        #expect(timeline.firstWeekIndex(of: october) == 49)
        #expect(timeline.days(inWeek: 49).first == TestSupport.day(2026, 9, 27))
        #expect(timeline.displayedMonth(topWeek: 49) == october)
    }

    @Test func 表示月は見えている6週の上から3行目と4行目の境目にある週の中央の日の月になる() throws {
        let timeline = try timeline()
        let september = try CalendarMonth(year: 2026, month: 9)
        let october = try CalendarMonth(year: 2026, month: 10)

        // 一番上が 46 なら中央の週は 49（9/27〜10/3）で、中央の日は 9/30。
        #expect(timeline.displayedMonth(topWeek: 46) == september)
        // 一番上が 47 なら中央の週は 50（10/4〜10/10）で、中央の日は 10/7。
        #expect(timeline.displayedMonth(topWeek: 47) == october)
        // 10 月の最終週 10/25〜10/31（番号 53）の中央の日は 10/28。
        #expect(timeline.displayedMonth(topWeek: 53 - 3) == october)
        // 次の週 11/1〜11/7（番号 54）の中央の日は 11/4。
        #expect(timeline.displayedMonth(topWeek: 54 - 3) == (try CalendarMonth(year: 2026, month: 11)))
    }

    @Test func 月の最初の週を一番上にするとその月が表示月になる() throws {
        for firstWeekday in 1...7 {
            let timeline = try timeline(firstWeekday: firstWeekday, weeksOnEachSide: 200)
            for year in [2024, 2026] {
                for month in 1...12 {
                    let target = try CalendarMonth(year: year, month: month)
                    let first = try #require(timeline.firstWeekIndex(of: target))
                    #expect(timeline.displayedMonth(topWeek: first) == target)
                }
            }
        }
    }

    @Test func 範囲外の番号は端の週に丸める() throws {
        let timeline = try timeline(weeksOnEachSide: 10)

        #expect(timeline.displayedMonth(topWeek: -100) == timeline.displayedMonth(topWeek: -3))
        #expect(timeline.displayedMonth(topWeek: 1_000) == timeline.displayedMonth(topWeek: timeline.weekCount - 1 - 3))
        #expect(timeline.days(inWeek: -1).isEmpty)
        #expect(timeline.days(inWeek: timeline.weekCount).isEmpty)
        #expect(timeline.firstDay(ofWeek: timeline.weekCount) == nil)
    }

    @Test func 並びの端の月は一番上に置けない() throws {
        let timeline = try timeline(weeksOnEachSide: 10)

        // 今日の 10 週後は 2027-01 初め。6 週分が並びに収まらない月は進めない。
        #expect(timeline.canShow(try CalendarMonth(year: 2026, month: 10)))
        #expect(!timeline.canShow(try CalendarMonth(year: 2027, month: 1)))
        #expect(!timeline.canShow(try CalendarMonth(year: 2030, month: 1)))
        #expect(!timeline.canShow(try CalendarMonth(year: 2020, month: 1)))
    }

    @Test func 週の番号の範囲が覆う日の範囲を並びの内側に切り詰めて返す() throws {
        let timeline = try timeline()
        let range = try #require(timeline.dayRange(weeks: 49..<59))

        #expect(range.start == TestSupport.day(2026, 9, 27))
        #expect(range.end == TestSupport.day(2026, 9, 27).adding(days: 70, calendar: calendar))
        let clamped = try #require(timeline.dayRange(weeks: -5..<3))
        #expect(clamped.start == timeline.firstDay(ofWeek: 0))
        #expect(timeline.dayRange(weeks: 2_000..<2_010) == nil)
    }

    @Test func 日を番号で引ける() throws {
        let timeline = try timeline()
        let range = timeline.selectableDayRange

        #expect(timeline.dayCount == range.days(calendar: calendar).count)
        #expect(timeline.day(at: 0) == range.start)
        #expect(timeline.day(at: timeline.dayCount - 1) == range.end.adding(days: -1, calendar: calendar))
        #expect(timeline.day(at: timeline.dayIndex(of: today) ?? -1) == today)
        #expect(timeline.day(at: -1) == nil)
        #expect(timeline.day(at: timeline.dayCount) == nil)
    }

    @Test func 日の番号は日から逆引きでき_選べる日の外はnilにする() throws {
        let timeline = try timeline()
        let range = timeline.selectableDayRange

        for index in [0, 1, 364, timeline.dayCount - 1] {
            let day = try #require(timeline.day(at: index))
            #expect(timeline.dayIndex(of: day) == index)
        }
        #expect(timeline.dayIndex(of: range.start.adding(days: -1, calendar: calendar)) == nil)
        #expect(timeline.dayIndex(of: range.end) == nil)
    }

    @Test func 選べる日の範囲は表示できる最初の月の1日から最後の月の末日まで() throws {
        for firstWeekday in 1...7 {
            let timeline = try timeline(firstWeekday: firstWeekday)
            let range = timeline.selectableDayRange
            let first = CalendarMonth(containing: range.start)
            let last = CalendarMonth(containing: range.end.adding(days: -1, calendar: calendar))

            #expect(range.start == first.firstDay)
            #expect(range.end == last.next.firstDay)
            #expect(timeline.canShow(first))
            #expect(timeline.canShow(last))
            #expect(!timeline.canShow(first.previous))
            #expect(!timeline.canShow(last.next))
            // 並び全体の中に収まり、端の行に見える表示できない月の日は含まない。
            #expect(range.start >= timeline.fullDayRange.start)
            #expect(range.end <= timeline.fullDayRange.end)
            // 今日の週の前後 52 週は、先頭と末尾でそれぞれ最大 1 か月ほど狭まる。
            #expect(range.days(calendar: calendar).count >= 52 * 2 * 7 - 62 * 2)
        }
    }

    @Test func 選べる日は表示できる月の日だけ() throws {
        // 2026-10-24（日曜始まり）の前後 52 週は 2025-10-19 から始まるので、2025-10 は表示できず、2025-11-01 から選べる。
        let timeline = try timeline()

        #expect(!timeline.canShow(try CalendarMonth(year: 2025, month: 10)))
        #expect(timeline.selectableDayRange.start == TestSupport.day(2025, 11, 1))
        #expect(!timeline.isSelectable(TestSupport.day(2025, 10, 31)))
        #expect(timeline.isSelectable(TestSupport.day(2025, 11, 1)))
        #expect(timeline.isSelectable(today))
        let lastDay = timeline.selectableDayRange.end.adding(days: -1, calendar: calendar)
        #expect(timeline.isSelectable(lastDay))
        #expect(!timeline.isSelectable(lastDay.adding(days: 1, calendar: calendar)))
        // 選べる日は、すべて表示できる月の日である。
        for day in timeline.selectableDayRange.days(calendar: calendar) {
            #expect(timeline.canShow(day.calendarMonth))
        }
    }

    @Test func 表示できる月がない短い並びでは並び全体を選べる() throws {
        let timeline = try timeline(weeksOnEachSide: 2)

        #expect(timeline.selectableDayRange == timeline.fullDayRange)
    }

    @Test func 並び全体の日の範囲は最初の週の最初の日から最後の週の最後の日まで() throws {
        let timeline = try timeline()
        let range = timeline.fullDayRange

        #expect(range.start == timeline.firstDay(ofWeek: 0))
        #expect(range.end == timeline.days(inWeek: timeline.weekCount - 1).last?.adding(days: 1, calendar: calendar))
        #expect(range.days(calendar: calendar).count == timeline.weekCount * 7)
    }

    @Test func 対応年の端では並べる週を減らす() throws {
        let early = try timeline(today: TestSupport.day(1, 1, 10))
        #expect(early.firstDay(ofWeek: 0).map { $0 >= TestSupport.day(1, 1, 1) } == true)
        #expect(early.todayWeekIndex <= 1)

        let late = try timeline(today: TestSupport.day(9999, 12, 20))
        let last = late.days(inWeek: late.weekCount - 1).last
        #expect(last.map { $0 <= TestSupport.day(9999, 12, 31) } == true)
    }
}
