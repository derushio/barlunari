import Foundation
import MenuDateDomain
import MenuDatePreviewSupport
import Testing

@testable import MenuDatePresentation

/// 予定一覧の日と選べる日がマス目の表示できる月の日だけであること、今日を含む週が変わったときの週の並びの作り直し。
@MainActor
@Suite struct SelectableRangeTests {
    static let calendar = SampleData.calendar

    func month(_ year: Int, _ month: Int) -> CalendarMonth {
        try! CalendarMonth(year: year, month: month)
    }

    func timeline(today: CalendarDay = SampleData.today) throws -> WeekTimeline {
        try WeekTimeline(today: today, firstWeekday: Self.calendar.firstWeekday)
    }

    // MARK: - 範囲の端

    @Test func 一覧を先頭までスクロールしても表示月とマス目と選択日が食い違わない() async throws {
        let viewModel = await Harness().loadedPopover()
        let timeline = try timeline()
        let first = viewModel.agendaRange.start
        let before = viewModel.gridScrollRequest

        viewModel.agendaDidScroll(toTopDay: first)

        #expect(viewModel.selectedDay == first)
        #expect(viewModel.displayedMonth == first.calendarMonth)
        #expect(timeline.canShow(viewModel.displayedMonth))
        #expect(viewModel.gridScrollRequest != before)
        #expect(viewModel.gridScrollRequest?.weekIndex == timeline.firstWeekIndex(of: first.calendarMonth))
    }

    @Test func 一覧を末尾までスクロールしても表示月とマス目と選択日が食い違わない() async throws {
        let viewModel = await Harness().loadedPopover()
        let timeline = try timeline()
        let last = viewModel.agendaRange.end.adding(days: -1, calendar: Self.calendar)
        let before = viewModel.gridScrollRequest

        viewModel.agendaDidScroll(toTopDay: last)

        #expect(viewModel.selectedDay == last)
        #expect(viewModel.displayedMonth == last.calendarMonth)
        #expect(timeline.canShow(viewModel.displayedMonth))
        #expect(viewModel.gridScrollRequest != before)
        #expect(viewModel.gridScrollRequest?.weekIndex == timeline.firstWeekIndex(of: last.calendarMonth))
    }

    @Test func 範囲の外の日へ一覧がスクロールしても選択日も表示月も変えない() async {
        let viewModel = await Harness().loadedPopover()
        let outside = viewModel.agendaRange.start.adding(days: -1, calendar: Self.calendar)
        let selected = viewModel.selectedDay
        let displayed = viewModel.displayedMonth

        viewModel.agendaDidScroll(toTopDay: outside)

        #expect(viewModel.selectedDay == selected)
        #expect(viewModel.displayedMonth == displayed)
    }

    @Test func マス目の端の行にある表示できない月の日は選べない() async throws {
        let viewModel = await Harness().loadedPopover()
        let timeline = try timeline()
        let edgeDay = viewModel.agendaRange.start.adding(days: -1, calendar: Self.calendar)
        #expect(timeline.dayRange(weeks: 0..<2)?.contains(edgeDay) == true)
        let selected = viewModel.selectedDay
        let displayed = viewModel.displayedMonth
        let grid = viewModel.gridScrollRequest
        let agenda = viewModel.agendaScrollRequest

        viewModel.select(edgeDay)

        #expect(viewModel.selectedDay == selected)
        #expect(viewModel.displayedMonth == displayed)
        #expect(viewModel.gridScrollRequest == grid)
        #expect(viewModel.agendaScrollRequest == agenda)
    }

    @Test func 端の行の表示できない月の日は選べない状態で返し_表示できる月の日は選べる() async {
        let viewModel = await Harness().loadedPopover()
        let range = viewModel.agendaRange

        let firstRow = viewModel.weekCells(at: 0)
        #expect(firstRow.contains { !$0.isSelectable })
        for cell in firstRow { #expect(cell.isSelectable == range.contains(cell.day)) }
        let lastRow = viewModel.weekCells(at: viewModel.weekCount - 1)
        #expect(lastRow.contains { !$0.isSelectable })
        #expect(viewModel.weekCells(at: viewModel.displayedMonthFirstWeek).allSatisfy { $0.isSelectable })
    }

    @Test func マス目を先頭と末尾までスクロールしても表示月は表示できる月に収まる() async throws {
        let viewModel = await Harness().loadedPopover()
        let timeline = try timeline()

        viewModel.gridDidScroll(toTopWeek: 0)
        #expect(timeline.canShow(viewModel.displayedMonth))
        #expect(viewModel.displayedMonth == viewModel.agendaRange.start.calendarMonth)

        viewModel.gridDidScroll(toTopWeek: timeline.weekCount - WeekTimeline.visibleWeekCount)
        #expect(timeline.canShow(viewModel.displayedMonth))
        let last = viewModel.agendaRange.end.adding(days: -1, calendar: Self.calendar)
        #expect(viewModel.displayedMonth == last.calendarMonth)
    }

    @Test func 予定一覧のどの日も表示できる月の日である() async throws {
        let viewModel = await Harness().loadedPopover()
        let timeline = try timeline()

        for index in [0, 1, viewModel.agendaDayCount / 2, viewModel.agendaDayCount - 1] {
            let day = try #require(viewModel.agendaDay(at: index))
            #expect(timeline.canShow(day.calendarMonth))
        }
    }

    // MARK: - 日付が進んだとき

    @Test func 起動から1年以上経っても今日がマス目と一覧の範囲に入る() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let later = SampleData.date(2027, 12, 15, 9, 0)
        let laterDay = SampleData.day(2027, 12, 15)
        #expect(viewModel.agendaIndex(of: laterDay) == nil)
        let grid = viewModel.gridScrollRequest
        let agenda = viewModel.agendaScrollRequest

        harness.dateProvider.set(later)
        viewModel.systemCalendarDidChange()

        #expect(viewModel.today == laterDay)
        #expect(viewModel.selectedDay == laterDay)
        #expect(viewModel.displayedMonth == month(2027, 12))
        let index = try #require(viewModel.agendaIndex(of: laterDay))
        #expect(viewModel.agendaDay(at: index) == laterDay)
        let rebuilt = try timeline(today: laterDay)
        #expect(viewModel.agendaRange == rebuilt.selectableDayRange)
        #expect(viewModel.gridScrollRequest != grid)
        #expect(viewModel.gridScrollRequest?.weekIndex == rebuilt.firstWeekIndex(of: month(2027, 12)))
        #expect(viewModel.agendaScrollRequest != agenda)
        #expect(viewModel.agendaScrollRequest?.day == laterDay)
        let first = viewModel.displayedMonthFirstWeek
        let visible = (first..<(first + WeekTimeline.visibleWeekCount)).flatMap { viewModel.weekCells(at: $0) }
        #expect(visible.contains { $0.isToday })
    }

    @Test func ポップオーバーを開いたときに日付が1年以上進んでいても今日の週で並びを作り直す() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let laterDay = SampleData.day(2028, 3, 3)
        let grid = viewModel.gridScrollRequest
        let agenda = viewModel.agendaScrollRequest

        harness.dateProvider.set(SampleData.date(2028, 3, 3, 9, 0))
        viewModel.popoverDidAppear()
        await viewModel.waitForLoad()

        let rebuilt = try timeline(today: laterDay)
        #expect(viewModel.agendaRange == rebuilt.selectableDayRange)
        #expect(viewModel.selectedDay == laterDay)
        #expect(viewModel.displayedMonth == month(2028, 3))
        #expect(viewModel.gridScrollRequest != grid)
        #expect(viewModel.gridScrollRequest?.weekIndex == rebuilt.firstWeekIndex(of: month(2028, 3)))
        #expect(viewModel.agendaScrollRequest != agenda)
        #expect(viewModel.agendaScrollRequest?.day == laterDay)
        #expect(viewModel.fetchRange.contains(laterDay))
        let todayIndex = try #require(viewModel.agendaIndex(of: laterDay))
        #expect(viewModel.agendaSection(at: todayIndex)?.isLoaded == true)
    }

    @Test func 今日の週が同じなら日付が変わっても並びを作り直さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let range = viewModel.agendaRange
        let week = viewModel.displayedMonthFirstWeek

        // 2026-10-24 は土曜日。日曜始まりの同じ週の 10/20 に戻る。
        harness.dateProvider.set(SampleData.date(2026, 10, 20, 9, 0))
        viewModel.systemCalendarDidChange()

        #expect(viewModel.selectedDay == SampleData.day(2026, 10, 20))
        #expect(viewModel.agendaRange == range)
        #expect(viewModel.displayedMonthFirstWeek == week)
    }

    @Test func 今日の週が変わって選択日が範囲の端にあっても選べる範囲に収まる() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.agendaDidScroll(toTopDay: viewModel.agendaRange.start)

        harness.dateProvider.set(SampleData.date(2026, 10, 26, 9, 0))
        viewModel.systemCalendarDidChange()

        #expect(viewModel.agendaRange.contains(viewModel.selectedDay))
        #expect(viewModel.agendaIndex(of: viewModel.selectedDay) != nil)
    }
}
