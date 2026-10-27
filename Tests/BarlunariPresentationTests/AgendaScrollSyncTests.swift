import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

/// 予定一覧の固定の範囲、取得範囲、スクロールと選択日の同期。
@MainActor
@Suite struct AgendaScrollSyncTests {
    static let calendar = SampleData.calendar
    typealias ViewModel = CalendarPopoverViewModel

    func day(_ offset: Int, from base: CalendarDay = SampleData.today) -> CalendarDay {
        base.adding(days: offset, calendar: Self.calendar)
    }

    func dayCount(_ range: DayRange) -> Int { range.days(calendar: Self.calendar).count }

    // MARK: - 固定の範囲

    @Test func 範囲はマス目が表示できる月の日だけで要求は出さない() throws {
        let viewModel = Harness().popover
        let timeline = try WeekTimeline(today: SampleData.today, firstWeekday: Self.calendar.firstWeekday)
        let range = viewModel.agendaRange

        #expect(range == timeline.selectableDayRange)
        #expect(viewModel.agendaDayCount == timeline.dayCount)
        #expect(dayCount(range) == viewModel.agendaDayCount)
        // 範囲の端の月は、どちらもマス目が一番上に置ける月である。
        #expect(range.start == CalendarMonth(containing: range.start).firstDay)
        #expect(timeline.canShow(CalendarMonth(containing: range.start)))
        #expect(timeline.canShow(CalendarMonth(containing: range.end.adding(days: -1, calendar: Self.calendar))))
        #expect(range.contains(SampleData.today))
        #expect(viewModel.agendaScrollRequest == nil)
    }

    @Test func 範囲はスクロールでも日の選択でも読み込みでも変わらない() async {
        let viewModel = Harness().popover
        let range = viewModel.agendaRange

        viewModel.reload()
        await viewModel.waitForLoad()
        viewModel.agendaDidScroll(toTopDay: range.start)
        viewModel.agendaDidScroll(toTopDay: range.end.adding(days: -1, calendar: Self.calendar))
        viewModel.select(SampleData.day(2027, 6, 15))
        viewModel.showToday()
        await viewModel.waitForLoad()

        #expect(viewModel.agendaRange == range)
        #expect(viewModel.agendaDayCount == dayCount(range))
    }

    @Test func 番号の日は範囲の最初の日から順に並ぶ() {
        let viewModel = Harness().popover
        let range = viewModel.agendaRange

        #expect(viewModel.agendaDay(at: 0) == range.start)
        #expect(viewModel.agendaDay(at: viewModel.agendaDayCount - 1) == range.end.adding(days: -1, calendar: Self.calendar))
        #expect(viewModel.agendaSection(at: 0)?.day == range.start)
    }

    // MARK: - 取得範囲

    @Test func 取得範囲は予定一覧の全範囲で一度の読み込みで取得する() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()

        #expect(viewModel.fetchRange == viewModel.agendaRange)
        #expect(await harness.eventRepository.requests == [viewModel.fetchRange.dateInterval(calendar: Self.calendar)])
    }

    @Test func 選択日が変わっても取得範囲は変わらない() async {
        let viewModel = await Harness().loadedPopover()
        let range = viewModel.fetchRange

        viewModel.select(SampleData.day(2027, 6, 30))
        #expect(viewModel.fetchRange == range)
        viewModel.agendaDidScroll(toTopDay: viewModel.agendaRange.start)
        #expect(viewModel.fetchRange == range)
    }

    @Test func 範囲の端の日までスクロールしても読み込み直さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count
        let first = viewModel.agendaRange.start
        let last = viewModel.agendaRange.end.adding(days: -1, calendar: Self.calendar)

        for target in [last, first, last, first] {
            viewModel.agendaDidScroll(toTopDay: target)
            await viewModel.waitForLoad()
        }

        #expect(await harness.eventRepository.requests.count == before)
        #expect(viewModel.section(of: last).isLoaded)
        #expect(viewModel.section(of: first).isLoaded)
    }

    @Test func 範囲の中を一日ずつスクロールしても読み込み直さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        for offset in [1, 2, 3, 4, 5, 4, 3, 2, 1, 0, -1, -2, -3, -4, -5, -6, -7, 60, 120, -60] {
            viewModel.agendaDidScroll(toTopDay: day(offset))
        }
        await viewModel.waitForLoad()

        #expect(await harness.eventRepository.requests.count == before)
    }

    // MARK: - 利用者のスクロール

    @Test func 利用者のスクロールで選択日と表示月を一番上の日に合わせる() async {
        let viewModel = await Harness().loadedPopover()

        viewModel.agendaDidScroll(toTopDay: SampleData.day(2026, 11, 3))

        #expect(viewModel.selectedDay == SampleData.day(2026, 11, 3))
        #expect(viewModel.displayedMonth == SampleData.day(2026, 11, 3).calendarMonth)
        #expect(viewModel.monthTitle == "2026年11月")
        #expect(viewModel.weeks.flatMap { $0 }.first { $0.isSelected }?.day == SampleData.day(2026, 11, 3))
    }

    @Test func 利用者のスクロールではスクロールの要求を出さない() async {
        let viewModel = await Harness().loadedPopover()
        let before = viewModel.agendaScrollRequest

        viewModel.agendaDidScroll(toTopDay: day(5))
        viewModel.agendaDidScroll(toTopDay: day(9))

        #expect(viewModel.agendaScrollRequest == before)
    }

    @Test func 利用者のスクロールでは詳細を閉じず詳細の間は選択日を変えない() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try #require(viewModel.selectedSection.rows.first))
        let detailID = viewModel.detailEventID
        let request = viewModel.agendaScrollRequest

        viewModel.agendaDidScroll(toTopDay: day(3))

        #expect(viewModel.detailEventID == detailID)
        #expect(viewModel.selectedDay == SampleData.today)
        #expect(viewModel.agendaScrollRequest == request)
    }

    @Test func 範囲の外の日のスクロールは無視する() async {
        let viewModel = await Harness().loadedPopover()
        let range = viewModel.agendaRange

        viewModel.agendaDidScroll(toTopDay: day(4_000))

        #expect(viewModel.selectedDay == SampleData.today)
        #expect(viewModel.agendaRange == range)
    }

    @Test func スクロールで選択日が変わっても月の読み込み済みの範囲内なら読み込み直さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        viewModel.agendaDidScroll(toTopDay: day(3))
        await viewModel.waitForLoad()

        #expect(await harness.eventRepository.requests.count == before)
    }

    // MARK: - ViewModel の操作によるスクロールの要求

    @Test func マス目の日を選ぶとその日を一番上にするスクロールを求める() async {
        let viewModel = await Harness().loadedPopover()

        viewModel.select(SampleData.day(2026, 10, 27))

        #expect(viewModel.agendaScrollRequest?.day == SampleData.day(2026, 10, 27))
    }

    @Test func 同じ日を続けて選んでも別の要求になる() async throws {
        let viewModel = await Harness().loadedPopover()

        viewModel.select(SampleData.day(2026, 10, 27))
        let first = try #require(viewModel.agendaScrollRequest)
        viewModel.select(SampleData.day(2026, 10, 27))
        let second = try #require(viewModel.agendaScrollRequest)

        #expect(first.day == second.day)
        #expect(first != second)
        #expect(second.serial == first.serial + 1)
    }

    @Test func 今日を押すと今日を一番上にするスクロールを求める() async {
        let viewModel = await Harness().loadedPopover()
        viewModel.select(SampleData.day(2026, 10, 30))

        viewModel.showToday()

        #expect(viewModel.agendaScrollRequest?.day == SampleData.today)
        #expect(viewModel.selectedDay == SampleData.today)
    }

    @Test func 月の移動は新しい選択日へのスクロールを求める() async {
        let viewModel = await Harness().loadedPopover()

        viewModel.showNextMonth()
        #expect(viewModel.agendaScrollRequest?.day == SampleData.day(2026, 11, 1))
        viewModel.showPreviousMonth()
        #expect(viewModel.agendaScrollRequest?.day == SampleData.today)
    }

    @Test func 日付が変わって選択日が今日に戻るときもスクロールを求める() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.select(SampleData.day(2026, 10, 30))
        let before = viewModel.agendaScrollRequest

        harness.dateProvider.set(SampleData.date(2026, 10, 25, 9, 0))
        viewModel.popoverDidAppear()

        #expect(viewModel.agendaScrollRequest?.day == SampleData.day(2026, 10, 25))
        #expect(viewModel.agendaScrollRequest != before)
    }

    @Test func 遠い日を選んでも範囲は変わらず_その日へのスクロールを求める() async {
        let viewModel = await Harness().loadedPopover()
        let range = viewModel.agendaRange
        let target = SampleData.day(2027, 6, 15)

        viewModel.select(target)

        #expect(viewModel.agendaRange == range)
        #expect(viewModel.agendaScrollRequest?.day == target)
        #expect(viewModel.agendaIndex(of: target) != nil)
        #expect(viewModel.fetchRange.contains(target))
    }

    @Test func 遠い日を選んでも全範囲が読み込み済みで読み込み直さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let target = SampleData.day(2027, 6, 15)
        let before = await harness.eventRepository.requests.count
        #expect(viewModel.section(of: target).isLoaded)

        viewModel.select(target)
        await viewModel.waitForLoad()

        #expect(await harness.eventRepository.requests.count == before)
        #expect(viewModel.section(of: target).isLoaded)
        #expect(viewModel.section(of: day(14, from: target)).isLoaded)
        #expect(viewModel.section(of: day(-14, from: target)).isLoaded)
    }

    // MARK: - 詳細の開閉

    @Test func 詳細を開閉しても選択日とスクロールの要求は変わらない() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.select(SampleData.day(2026, 10, 26))
        let request = viewModel.agendaScrollRequest
        let range = viewModel.agendaRange

        viewModel.showDetail(of: try #require(viewModel.selectedSection.rows.first))
        #expect(viewModel.eventDetail != nil)
        viewModel.closeDetail()

        #expect(viewModel.eventDetail == nil)
        #expect(viewModel.selectedDay == SampleData.day(2026, 10, 26))
        #expect(viewModel.agendaScrollRequest == request)
        #expect(viewModel.agendaRange == range)
    }
}
