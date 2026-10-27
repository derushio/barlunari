import Foundation
import MenuDateApplication
import MenuDateDomain
import MenuDatePreviewSupport
import Testing

@testable import MenuDatePresentation

/// 週の行が連続して流れる月のマス目と ViewModel の同期。
@MainActor
@Suite struct MonthGridScrollTests {
    static let calendar = SampleData.calendar

    func month(_ year: Int, _ month: Int) -> CalendarMonth { SampleData.day(year, month, 1).calendarMonth }

    // MARK: - 週の並び

    @Test func 週は今日を含む週の前後に1年分並び日はその週から読める() async {
        let viewModel = await Harness().loadedPopover()

        #expect(viewModel.weekCount == 105)
        let today = viewModel.weekCells(at: 52)
        #expect(today.map(\.day.day) == [18, 19, 20, 21, 22, 23, 24])
        #expect(today.first { $0.day == SampleData.today }?.isToday == true)
        #expect(viewModel.weekCells(at: -1).isEmpty)
        #expect(viewModel.weekCells(at: 105).isEmpty)
    }

    @Test func 初期の一番上の週は表示月の最初の週でそれより前の月の日は薄い扱いになる() async {
        let viewModel = await Harness().loadedPopover()

        #expect(viewModel.displayedMonthFirstWeek == 49)
        let first = viewModel.weekCells(at: viewModel.displayedMonthFirstWeek)
        #expect(first.map(\.isInMonth) == [false, false, false, false, true, true, true])
        // 表示月の外の日にも、取得済みの予定の点が出る。
        #expect(viewModel.weekCells(at: 43).allSatisfy { !$0.isInMonth })
    }

    // MARK: - 利用者のスクロール

    @Test func マス目のスクロールは表示月だけを変え選択日と一覧と詳細は変えない() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try #require(viewModel.selectedSection.rows.first))
        let selected = viewModel.selectedDay
        let agendaRequest = viewModel.agendaScrollRequest
        let gridRequest = viewModel.gridScrollRequest
        let range = viewModel.agendaRange

        // 一番上を 46 にすると、中央の週は 9/27〜10/3 で、中央の日は 9/30。
        viewModel.gridDidScroll(toTopWeek: 46)

        #expect(viewModel.displayedMonth == month(2026, 9))
        #expect(viewModel.selectedDay == selected)
        #expect(viewModel.agendaScrollRequest == agendaRequest)
        #expect(viewModel.agendaRange == range)
        #expect(viewModel.eventDetail != nil)
        // 利用者のスクロールでは、マス目へのスクロールを求めない。
        #expect(viewModel.gridScrollRequest == gridRequest)
    }

    @Test func 表示月が変わらないスクロールでは読み込み直さず要求も出さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        viewModel.gridDidScroll(toTopWeek: 48)
        viewModel.gridDidScroll(toTopWeek: 50)
        await viewModel.waitForLoad()

        #expect(viewModel.displayedMonth == month(2026, 10))
        #expect(await harness.eventRepository.requests.count == before)
        #expect(viewModel.gridScrollRequest == nil)
    }

    @Test func スクロールで月が変わっても予定を読み込み直さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        // 1 年後へ。取得範囲は全範囲なので読み込み直さない。
        let target = viewModel.weekCount / 2 + 52
        viewModel.gridDidScroll(toTopWeek: target)
        await viewModel.waitForLoad()

        #expect(viewModel.displayedMonth.year == 2027)
        #expect(await harness.eventRepository.requests.count == before)
        #expect(viewModel.phase == .loaded)
    }

    // MARK: - ViewModel の操作によるスクロールの要求

    @Test func 月の移動と今日は表示月の最初の週へのスクロールを求める() async {
        let viewModel = await Harness().loadedPopover()

        viewModel.showNextMonth()
        // 11/1 は日曜日なので、11 月の最初の週は 11/1 始まりで、今日の週の 2 週後。
        #expect(viewModel.gridScrollRequest?.weekIndex == 54)
        let serial = viewModel.gridScrollRequest?.serial

        viewModel.showToday()
        #expect(viewModel.gridScrollRequest?.weekIndex == 49)
        #expect(viewModel.gridScrollRequest?.serial != serial)
        // 同じ月の「今日」でも、利用者がずらした位置から戻すために別の要求を出す。
        let again = viewModel.gridScrollRequest?.serial
        viewModel.showToday()
        #expect(viewModel.gridScrollRequest?.serial != again)
    }

    @Test func 別の月の日の選択はその月へのスクロールを求め同じ月の日の選択は求めない() async {
        let viewModel = await Harness().loadedPopover()

        viewModel.select(SampleData.day(2026, 10, 27))
        #expect(viewModel.gridScrollRequest == nil)

        viewModel.select(SampleData.day(2026, 11, 3))
        #expect(viewModel.displayedMonth == month(2026, 11))
        #expect(viewModel.gridScrollRequest?.weekIndex == 54)
    }

    @Test func マス目をスクロールしてから日を選ぶと選択され一覧のスクロールを求める() async {
        let viewModel = await Harness().loadedPopover()
        viewModel.gridDidScroll(toTopWeek: 46)
        #expect(viewModel.displayedMonth == month(2026, 9))

        // 表示月の 9 月の日を選ぶ。マス目は動かさない。
        viewModel.select(SampleData.day(2026, 9, 29))

        #expect(viewModel.selectedDay == SampleData.day(2026, 9, 29))
        #expect(viewModel.agendaScrollRequest?.day == SampleData.day(2026, 9, 29))
        #expect(viewModel.gridScrollRequest == nil)
        #expect(viewModel.displayedMonth == month(2026, 9))
    }

    @Test func 予定一覧のスクロールで月をまたぐとマス目のスクロールを求める() async {
        let viewModel = await Harness().loadedPopover()

        viewModel.agendaDidScroll(toTopDay: SampleData.day(2026, 11, 2))

        #expect(viewModel.displayedMonth == month(2026, 11))
        #expect(viewModel.gridScrollRequest?.weekIndex == 54)
        let request = viewModel.gridScrollRequest

        // 同じ月の中のスクロールでは求めない。
        viewModel.agendaDidScroll(toTopDay: SampleData.day(2026, 11, 5))
        #expect(viewModel.gridScrollRequest == request)
    }

    @Test func 日付が変わって今日に戻るときもマス目のスクロールを求める() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.showNextMonth()
        let before = viewModel.gridScrollRequest

        harness.dateProvider.set(SampleData.date(2026, 10, 25, 9, 0))
        viewModel.popoverDidAppear()

        #expect(viewModel.displayedMonth == month(2026, 10))
        #expect(viewModel.gridScrollRequest != before)
        // 10/25 は新しい週の始まりなので、週の並びを作り直す。番号は作り直した並びで振る。
        let rebuilt = try WeekTimeline(today: SampleData.day(2026, 10, 25), firstWeekday: SampleData.calendar.firstWeekday)
        #expect(viewModel.gridScrollRequest?.weekIndex == rebuilt.firstWeekIndex(of: month(2026, 10)))
    }

    @Test func 週の開始曜日が変わると週の番号を振り直しマス目のスクロールを求める() async {
        let dateProvider = MutableDateProvider()
        let viewModel = await Harness(dateProvider: dateProvider).loadedPopover()
        #expect(viewModel.displayedMonthFirstWeek == 49)

        var calendar = SampleData.calendar
        calendar.firstWeekday = 2
        dateProvider.set(calendar: calendar)
        viewModel.systemCalendarDidChange()

        // 月曜始まりの 10 月の最初の週は 9/28 始まり。今日の週（10/19 始まり）の 3 週前。
        #expect(viewModel.weekCells(at: 49).first?.day == SampleData.day(2026, 9, 28))
        #expect(viewModel.gridScrollRequest?.weekIndex == 49)
    }

    @Test func 週の並びの外の月へは進めない() async {
        let viewModel = await Harness().loadedPopover()

        // 1 年先の月の近くまで進める。
        for _ in 0..<11 { viewModel.showNextMonth() }
        #expect(viewModel.displayedMonth == month(2027, 9))

        // 並びの端の近くで進めなくなり、それ以降は表示月も選択日も変わらない。
        for _ in 0..<40 { viewModel.showNextMonth() }
        let last = viewModel.displayedMonth
        let selected = viewModel.selectedDay
        viewModel.showNextMonth()
        #expect(viewModel.displayedMonth == last)
        #expect(viewModel.selectedDay == selected)
        #expect(last.year <= 2027)
    }

    // MARK: - 取得範囲

    @Test func 取得範囲はマス目のどの位置でも見える週をすべて含む() async {
        let viewModel = await Harness().loadedPopover()

        #expect(viewModel.fetchRange == viewModel.agendaRange)
        // どの位置で止まっても見える 6 週は、取得範囲に含まれる。
        for top in [44, 48, 52, 70] {
            viewModel.gridDidScroll(toTopWeek: top)
            let visibleStart = viewModel.weekCells(at: top).first?.day
            let visibleEnd = viewModel.weekCells(at: top + 5).last?.day
            #expect(visibleStart.map(viewModel.fetchRange.contains) == true)
            #expect(visibleEnd.map(viewModel.fetchRange.contains) == true)
        }
    }

    @Test func マス目を範囲の端までスクロールしても読み込み直さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        for top in [46, 41, 34, 20, 0, 60, 80, 100, viewModel.weekCount - 6, 49] {
            viewModel.gridDidScroll(toTopWeek: top)
            await viewModel.waitForLoad()
        }

        #expect(await harness.eventRepository.requests.count == before)
        #expect(viewModel.phase == .loaded)
    }

    @Test func 週の開始曜日が変わると新しい全範囲で読み込み直す() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        var calendar = SampleData.calendar
        calendar.firstWeekday = 2
        harness.dateProvider.set(calendar: calendar)
        viewModel.systemCalendarDidChange()
        await viewModel.waitForLoad()

        let requests = await harness.eventRepository.requests
        #expect(requests.count == before + 1)
        #expect(viewModel.fetchRange == viewModel.agendaRange)
        #expect(requests.last == viewModel.fetchRange.dateInterval(calendar: calendar))
        #expect(viewModel.phase == .loaded)
    }
}
