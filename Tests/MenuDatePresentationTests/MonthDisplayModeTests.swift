import Foundation
import MenuDateApplication
import MenuDateDomain
import MenuDatePreviewSupport
import Observation
import Synchronization
import Testing

@testable import MenuDatePresentation

@MainActor
@Suite struct MonthDisplayModeTests {
    static let busyDay = SampleData.day(2026, 10, 22)

    // MARK: - 表示モード

    @Test func 保存がなければ月表示で始まる() {
        #expect(Harness().popover.displayMode == .month)
    }

    @Test func 保存したモードで始まる() {
        #expect(Harness(displayMode: .compact).popover.displayMode == .compact)
    }

    @Test func モードを変えると保存する() {
        let harness = Harness()
        harness.popover.setDisplayMode(.compact)

        #expect(harness.popover.displayMode == .compact)
        #expect(harness.displayModeStore.savedModes == [.compact])
        #expect(harness.displayModeStore.load() == .compact)
    }

    @Test func 同じモードに変えても保存しない() {
        let harness = Harness()
        harness.popover.setDisplayMode(.month)

        #expect(harness.displayModeStore.savedModes.isEmpty)
    }

    @Test func モードを変えると詳細を閉じる() async throws {
        let harness = Harness(events: SampleData.monthViewEvents)
        let viewModel = await harness.loadedPopover()
        viewModel.showSchedule(of: Self.busyDay)
        let id = try #require(viewModel.selectedDaySchedule.blocks.first?.id)
        viewModel.showDetail(of: id)
        #expect(viewModel.detailEventID == id)

        viewModel.setDisplayMode(.compact)

        #expect(viewModel.detailEventID == nil)
    }

    @Test func モードを変えても読み込み直さず表示月と選択日を変えない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.select(SampleData.day(2026, 11, 3))
        let month = viewModel.displayedMonth
        let day = viewModel.selectedDay
        let before = await harness.eventRepository.requests.count

        viewModel.setDisplayMode(.compact)
        viewModel.setDisplayMode(.month)
        await viewModel.waitForLoad()

        #expect(viewModel.displayedMonth == month)
        #expect(viewModel.selectedDay == day)
        #expect(await harness.eventRepository.requests.count == before)
    }

    // MARK: - 日の欄

    @Test func 日を押すとその日が選択日になり日の欄はその日のスケジュールになる() async throws {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let month = viewModel.displayedMonth
        let gridRequest = viewModel.gridScrollRequest

        viewModel.showSchedule(of: Self.busyDay)

        #expect(viewModel.selectedDay == Self.busyDay)
        #expect(viewModel.displayedMonth == month)
        #expect(viewModel.gridScrollRequest == gridRequest)
        let schedule = viewModel.selectedDaySchedule
        #expect(schedule.day == Self.busyDay)
        #expect(schedule.blocks.count == 6)
        #expect(schedule.allDay.isEmpty)
        #expect(schedule.isLoaded)
    }

    @Test func 日を押すと詳細と表示するカレンダーの一覧を閉じる() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try #require(viewModel.selectedDaySchedule.blocks.first).id)
        #expect(viewModel.detailEventID != nil)
        viewModel.showSchedule(of: SampleData.day(2026, 10, 26))
        #expect(viewModel.detailEventID == nil)

        viewModel.openCalendarFilter()
        viewModel.showSchedule(of: SampleData.day(2026, 10, 24))
        #expect(!viewModel.isCalendarFilterOpen)
    }

    @Test func 選べない日では何もしない() async {
        let viewModel = await Harness().loadedPopover()
        viewModel.showSchedule(of: SampleData.day(2040, 1, 1))
        #expect(viewModel.selectedDay == SampleData.today)
    }

    @Test func 表示月の外の日を押すと表示月がその月に移る() async {
        let viewModel = await Harness().loadedPopover()
        viewModel.showSchedule(of: SampleData.day(2026, 11, 1))
        #expect(viewModel.displayedMonth == SampleData.day(2026, 11, 1).calendarMonth)
    }

    @Test func 詳細を閉じると選択日のスケジュールに戻る() async throws {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        viewModel.showSchedule(of: Self.busyDay)
        let id = try #require(viewModel.selectedDaySchedule.blocks.first?.id)

        viewModel.showDetail(of: id)
        #expect(viewModel.eventDetail?.id == id)
        #expect(viewModel.selectedDay == Self.busyDay)

        viewModel.closeDetail()
        #expect(viewModel.detailEventID == nil)
        #expect(viewModel.selectedDay == Self.busyDay)
        #expect(viewModel.selectedDaySchedule.day == Self.busyDay)
    }

    @Test func 読み込み済みにない予定の詳細は開かない() async {
        let viewModel = await Harness().loadedPopover()
        // 読み込む予定に含まれない予定。
        let unknown = SampleData.monthViewEvents.last!.id

        viewModel.showDetail(of: unknown)

        #expect(viewModel.detailEventID == nil)
    }

    // MARK: - 選択日のスケジュール

    @Test func 終日の予定は上部にまとめ時刻付きの予定はブロックになる() async throws {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        viewModel.showSchedule(of: SampleData.day(2026, 10, 23))
        let schedule = viewModel.selectedDaySchedule

        #expect(schedule.allDay.map(\.title) == ["創立記念日"])
        #expect(schedule.blocks.map(\.item.title) == ["週次定例", "障害対応", "確認", "ランチ", "設計会議", "電話"])
        let first = try #require(schedule.blocks.first)
        #expect(first.startMinute == 10 * 60)
        #expect(first.endMinute == 11 * 60)
        #expect(first.item.timeText == "10:00〜11:00")
        #expect(first.item.accessibilityLabel.hasPrefix("10:00〜11:00、週次定例、"))
    }

    @Test func 重なる予定は横に並び短い予定にも最小の長さがある() async throws {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        viewModel.showSchedule(of: SampleData.day(2026, 10, 23))
        let blocks = viewModel.selectedDaySchedule.blocks
        func block(_ title: String) throws -> DayScheduleBlock { try #require(blocks.first { $0.item.title == title }) }

        #expect(try block("週次定例").columnCount == 3)
        #expect(try block("障害対応").column == 1)
        #expect(try block("確認").column == 2)
        #expect(try block("ランチ").columnCount == 1)
        let phone = try block("電話")
        #expect(phone.startMinute == 16 * 60)
        #expect(phone.endMinute - phone.startMinute == DayTimelineLayout<Int>.minimumDisplayMinutes)
    }

    @Test func 日をまたぐ予定はその日の範囲で切り_丸ごと埋まる日は終日にまとめる() async throws {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        // 「社外ワークショップ」は 10/20 15:00 から 10/21 11:00。
        viewModel.showSchedule(of: SampleData.day(2026, 10, 20))
        let start = try #require(viewModel.selectedDaySchedule.blocks.first { $0.item.title == "社外ワークショップ" })
        #expect(start.startMinute == 15 * 60)
        #expect(start.endMinute == 1440)

        viewModel.showSchedule(of: SampleData.day(2026, 10, 21))
        let end = try #require(viewModel.selectedDaySchedule.blocks.first { $0.item.title == "社外ワークショップ" })
        #expect(end.startMinute == 0)
        #expect(end.endMinute == 11 * 60)

        // 「夜行バス」は 10/29 23:00 から 10/30 6:30。間に丸ごと埋まる日はない。
        viewModel.showSchedule(of: SampleData.day(2026, 10, 30))
        #expect(viewModel.selectedDaySchedule.blocks.first?.endMinute == 6 * 60 + 30)
    }

    @Test func 今日だけ現在時刻と相対の表示を持ち過去の予定を薄くする() async throws {
        let viewModel = await Harness().loadedPopover()
        let today = viewModel.selectedDaySchedule
        #expect(today.isToday)
        #expect(today.relativeLabel == "今日")
        #expect(today.currentMinute == 12 * 60)
        #expect(try #require(today.blocks.first { $0.item.title == "朝会" }).item.isPast)
        #expect(!(try #require(today.blocks.first { $0.item.title == "夕食" }).item.isPast))

        viewModel.showSchedule(of: SampleData.day(2026, 10, 25))
        let tomorrow = viewModel.selectedDaySchedule
        #expect(!tomorrow.isToday)
        #expect(tomorrow.relativeLabel == "明日")
        #expect(tomorrow.currentMinute == nil)
        #expect(tomorrow.allDay.map(\.title) == ["引っ越し"])
    }

    @Test func 読み込み前は読み込み中で予定がなければ空になる() async {
        let harness = Harness()
        #expect(!harness.popover.selectedDaySchedule.isLoaded)
        let viewModel = await harness.loadedPopover()
        viewModel.showSchedule(of: SampleData.day(2026, 10, 21))
        #expect(viewModel.selectedDaySchedule.isLoaded)
        #expect(viewModel.selectedDaySchedule.isEmpty)
    }

    @Test func 許可の案内では予定を表示できない状態になる() async {
        let harness = Harness(status: .denied)
        harness.popover.reload()
        await harness.popover.waitForLoad()
        #expect(harness.popover.selectedDaySchedule.isUnavailable)
    }

    @Test func 開いたときのスクロール位置は今日なら現在時刻の少し前になる() async {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        // 現在時刻は 12:00。11:00 に揃える。
        #expect(viewModel.selectedDaySchedule.scrollMinute == 11 * 60)
        // 10/23 の最初の時刻付きの予定は 10:00。その 60 分前。
        viewModel.showSchedule(of: SampleData.day(2026, 10, 23))
        #expect(viewModel.selectedDaySchedule.scrollMinute == 9 * 60)
        // 予定のない日は 8 時。
        viewModel.showSchedule(of: SampleData.day(2026, 10, 19))
        #expect(viewModel.selectedDaySchedule.scrollMinute == 8 * 60)
    }

    // MARK: - 閉じる契機

    /// 詳細を開いた状態を作る。
    func openedPopover(_ harness: Harness) async throws -> CalendarPopoverViewModel {
        let viewModel = await harness.loadedPopover()
        viewModel.showSchedule(of: Self.busyDay)
        viewModel.showDetail(of: try #require(viewModel.selectedDaySchedule.blocks.first?.id))
        return viewModel
    }

    func expectClosed(_ viewModel: CalendarPopoverViewModel) {
        #expect(viewModel.detailEventID == nil)
    }

    @Test func 日を選ぶと閉じる() async throws {
        let viewModel = try await openedPopover(Harness(events: SampleData.monthViewEvents))
        viewModel.select(SampleData.day(2026, 10, 26))
        expectClosed(viewModel)
    }

    @Test func 前月と翌月へ移ると閉じる() async throws {
        let viewModel = try await openedPopover(Harness(events: SampleData.monthViewEvents))
        viewModel.showNextMonth()
        expectClosed(viewModel)
        #expect(viewModel.selectedDaySchedule.day == viewModel.selectedDay)

        viewModel.showSchedule(of: SampleData.day(2026, 11, 10))
        viewModel.showPreviousMonth()
        expectClosed(viewModel)
    }

    @Test func 今日へ戻ると閉じる() async throws {
        let viewModel = try await openedPopover(Harness(events: SampleData.monthViewEvents))
        viewModel.showToday()
        expectClosed(viewModel)
    }

    @Test func ポップオーバーを開くと閉じる() async throws {
        let viewModel = try await openedPopover(Harness(events: SampleData.monthViewEvents))
        viewModel.popoverDidAppear()
        expectClosed(viewModel)
    }

    @Test func 日付が変わって今日に戻るときに閉じる() async throws {
        let dateProvider = MutableDateProvider()
        let viewModel = try await openedPopover(Harness(events: SampleData.monthViewEvents, dateProvider: dateProvider))

        dateProvider.set(SampleData.date(2026, 10, 25, 9, 0))
        viewModel.systemCalendarDidChange()

        expectClosed(viewModel)
        await viewModel.waitForLoad()
    }

    @Test func 読み直しで詳細の予定がなくなるとスケジュールに戻る() async throws {
        let harness = Harness(events: SampleData.monthViewEvents)
        let viewModel = try await openedPopover(harness)
        // 非表示にしたカレンダーの予定は、読み直すと一覧から消える。
        await harness.visibility.update { $0.hide(SampleData.workCalendar.id) }

        viewModel.reload()
        await viewModel.waitForLoad()

        #expect(viewModel.detailEventID == nil)
        #expect(viewModel.selectedDay == Self.busyDay)
    }

    @Test func エスケープは詳細を閉じ_次でパネルを閉じる() async throws {
        let viewModel = try await openedPopover(Harness(events: SampleData.monthViewEvents))
        #expect(viewModel.performEscape() == .closeDetail)
        #expect(viewModel.eventDetail == nil)
        #expect(viewModel.performEscape() == .closePanel)
    }

    // MARK: - monthWeek(at:)


    @Test func 週のマスの内容はweekCellsと同じである() async {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3

        let state = viewModel.monthWeek(at: week)

        #expect(state.cells == viewModel.weekCells(at: week))
        #expect(state.cells.map(\.day.day) == [18, 19, 20, 21, 22, 23, 24])
    }

    @Test func 週の予定の配置は取得済みの予定とカレンダーの色から作る() async throws {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let layout = viewModel.monthWeek(at: viewModel.displayedMonthFirstWeek + 3).layout

        // 10-22（列 4）の時刻付きの予定 6 件。
        let onBusyDay = layout.items.filter { $0.columns == 4..<5 }
        #expect(onBusyDay.count == 6)
        #expect(Set(onBusyDay.map(\.lane)) == Set(0..<6))
        // 10-20 から 10-21 にまたがる予定は、列 2〜3 のバー。
        let workshop = try #require(layout.items.first { $0.title == "社外ワークショップ" })
        #expect(workshop.columns == 2..<4)
        #expect(workshop.color == SampleData.workCalendar.color)
        #expect(workshop.kind == .bar(continuesFromPreviousWeek: false, continuesToNextWeek: false))
        // 今日（10-24）は 10-22 の予定より後なので、10-22 の予定は過去である。
        #expect(onBusyDay.allSatisfy { $0.isPast })
    }

    @Test func 週をまたぐ終日予定は両側の週で継続のフラグを持つ() async throws {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let first = viewModel.displayedMonthFirstWeek
        let trip10 = try #require(viewModel.monthWeek(at: first + 4).layout.items.first { $0.title == "出張" })
        let trip11 = try #require(viewModel.monthWeek(at: first + 5).layout.items.first { $0.title == "出張" })

        #expect(trip10.columns == 5..<7)
        #expect(trip10.kind == .bar(continuesFromPreviousWeek: false, continuesToNextWeek: true))
        #expect(trip11.columns == 0..<2)
        #expect(trip11.kind == .bar(continuesFromPreviousWeek: true, continuesToNextWeek: false))
    }

    @Test func 読み込み前は予定のない配置を返す() {
        let viewModel = Harness().popover
        #expect(viewModel.monthWeek(at: viewModel.displayedMonthFirstWeek).layout.items.isEmpty)
    }

    @Test func 範囲の端の週でも7日分のマスを返す() async {
        let viewModel = await Harness().loadedPopover()
        let last = viewModel.weekCount - 1
        #expect(viewModel.monthWeek(at: 0).cells.count == 7)
        #expect(viewModel.monthWeek(at: last).cells.count == 7)
    }

    @Test func 選択日の変化を観測できる() async {
        let viewModel = await Harness().loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        let changed = Mutex(false)
        withObservationTracking {
            _ = viewModel.monthWeek(at: week)
        } onChange: {
            changed.withLock { $0 = true }
        }

        viewModel.select(SampleData.day(2026, 10, 20))

        #expect(changed.withLock { $0 })
    }

    @Test func 読み込み結果の変化を観測できる() async {
        let harness = Harness(events: SampleData.monthViewEvents)
        let viewModel = harness.popover
        let week = viewModel.displayedMonthFirstWeek + 3
        let changed = Mutex(false)
        withObservationTracking {
            _ = viewModel.monthWeek(at: week)
        } onChange: {
            changed.withLock { $0 = true }
        }

        viewModel.reload()
        await viewModel.waitForLoad()

        #expect(changed.withLock { $0 })
        #expect(!viewModel.monthWeek(at: week).layout.items.isEmpty)
    }

    @Test func 表示月の変化を観測できる() async {
        let viewModel = await Harness().loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        let changed = Mutex(false)
        withObservationTracking {
            _ = viewModel.monthWeek(at: week)
        } onChange: {
            changed.withLock { $0 = true }
        }

        viewModel.showNextMonth()

        #expect(changed.withLock { $0 })
    }

    // MARK: - 層ごとの入口

    /// `read` が読んだ値が、`change` のあとに変わったと通知されたか。
    @Test func 週の開始曜日が変わると選択日の列と日のボタンの内容を読み直す() async {
        let dateProvider = MutableDateProvider()
        let viewModel = await Harness(dateProvider: dateProvider).loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        var monday = SampleData.calendar
        monday.firstWeekday = 2
        let change = {
            dateProvider.set(calendar: monday)
            viewModel.systemCalendarDidChange()
        }

        #expect(isInvalidated(by: change, reading: { _ = viewModel.selectedColumn(inWeek: week) }))
        dateProvider.set(calendar: SampleData.calendar)
        viewModel.systemCalendarDidChange()
        #expect(isInvalidated(by: change, reading: { _ = viewModel.dayAccessibility(inWeek: week) }))
    }

    private func isInvalidated(by change: () -> Void, reading read: () -> Void) -> Bool {
        let changed = Mutex(false)
        withObservationTracking {
            read()
        } onChange: {
            changed.withLock { $0 = true }
        }
        change()
        return changed.withLock { $0 }
    }

    @Test func 予定の層の入口は取得済みの予定とカレンダーの色から配置を作りmonthWeekと同じである() async {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3

        #expect(viewModel.monthWeekLayout(at: week) == viewModel.monthWeek(at: week).layout)
        #expect(viewModel.monthWeekLayout(at: week).items.contains { $0.color == SampleData.workCalendar.color })
    }

    @Test func 予定の層の入口は選択日と表示月と今日の変化で無効にならない() async {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3

        #expect(!isInvalidated(by: { viewModel.select(SampleData.day(2026, 10, 20)) }, reading: { _ = viewModel.monthWeekLayout(at: week) }))
        #expect(!isInvalidated(by: { viewModel.showNextMonth() }, reading: { _ = viewModel.monthWeekLayout(at: week) }))
        #expect(!isInvalidated(by: { viewModel.showToday() }, reading: { _ = viewModel.monthWeekLayout(at: week) }))
        #expect(!isInvalidated(by: { viewModel.gridDidScroll(toTopWeek: week + 5) }, reading: { _ = viewModel.monthWeekLayout(at: week) }))
    }

    @Test func 予定の層の入口は読み込み結果の変化で無効になる() async {
        let viewModel = Harness(events: SampleData.monthViewEvents).popover
        let week = viewModel.displayedMonthFirstWeek + 3
        let changed = Mutex(false)
        withObservationTracking {
            _ = viewModel.monthWeekLayout(at: week)
        } onChange: {
            changed.withLock { $0 = true }
        }

        viewModel.reload()
        await viewModel.waitForLoad()

        #expect(changed.withLock { $0 })
        #expect(!viewModel.monthWeekLayout(at: week).items.isEmpty)
    }

    @Test func マスの層の入口は選択日の変化でも表示月の変化でも無効にならない() async {
        let viewModel = await Harness().loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3

        #expect(!isInvalidated(by: { viewModel.select(SampleData.day(2026, 10, 20)) }, reading: { _ = viewModel.monthWeekDays(at: week) }))
        #expect(!isInvalidated(by: { viewModel.showNextMonth() }, reading: { _ = viewModel.monthWeekDays(at: week) }))
    }

    @Test func 覆いの層の入口は表示月の変化で無効になり選択日の変化で無効にならない() async {
        let viewModel = await Harness().loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3

        #expect(isInvalidated(by: { viewModel.showNextMonth() }, reading: { _ = viewModel.outOfMonthColumns(inWeek: week) }))
        let viewModelForSelection = await Harness().loadedPopover()
        let selectionWeek = viewModelForSelection.displayedMonthFirstWeek + 3
        #expect(!isInvalidated(by: { viewModelForSelection.select(SampleData.day(2026, 10, 20)) }, reading: { _ = viewModelForSelection.outOfMonthColumns(inWeek: selectionWeek) }))
    }

    @Test func 表示月の外の列は週の中で表示月に属さない日の列である() async {
        let viewModel = await Harness().loadedPopover()
        let first = viewModel.displayedMonthFirstWeek
        for week in [first - 1, first, first + 2, first + 4, first + 5] {
            let cells = viewModel.weekCells(at: week)
            let expected = cells.indices.filter { !cells[$0].isInMonth }
            #expect(viewModel.outOfMonthColumns(inWeek: week) == expected)
        }
        // 10 月の 4 週目（10-18〜10-24）は全部 10 月に入る。
        #expect(viewModel.outOfMonthColumns(inWeek: first + 3).isEmpty)
    }

    @Test func マスの層の入口の内容はweekCellsと同じである() async {
        let viewModel = await Harness().loadedPopover()
        let first = viewModel.displayedMonthFirstWeek
        for week in [0, first, first + 3, viewModel.weekCount - 1] {
            let days = viewModel.monthWeekDays(at: week)
            let cells = viewModel.weekCells(at: week)
            #expect(days.map(\.day) == cells.map(\.day))
            #expect(days.map(\.isToday) == cells.map(\.isToday))
            #expect(days.map(\.isSelectable) == cells.map(\.isSelectable))
            #expect(days.map(\.weekdayKind) == cells.map(\.weekdayKind))
        }
    }

    @Test func 週の開始曜日が月曜でもマスの層の曜日の種類は列から正しく決まる() async {
        var calendar = SampleData.calendar
        calendar.firstWeekday = 2
        let viewModel = await Harness(dateProvider: MutableDateProvider(calendar: calendar)).loadedPopover()
        let days = viewModel.monthWeekDays(at: viewModel.displayedMonthFirstWeek + 2)

        #expect(days.map(\.weekdayKind) == [.weekday, .weekday, .weekday, .weekday, .weekday, .saturday, .sunday])
        #expect(days.map(\.weekdayKind) == viewModel.weekCells(at: viewModel.displayedMonthFirstWeek + 2).map(\.weekdayKind))
    }

    @Test func 選択日の列は選択日のある週だけが持ち選択日の変化で無効になる() async {
        let viewModel = await Harness().loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        // 10-24（土）は、その週の最後の列。
        #expect(viewModel.selectedColumn(inWeek: week) == 6)
        #expect(viewModel.selectedColumn(inWeek: week + 1) == nil)

        #expect(isInvalidated(by: { viewModel.select(SampleData.day(2026, 10, 20)) }, reading: { _ = viewModel.selectedColumn(inWeek: week) }))
        #expect(viewModel.selectedColumn(inWeek: week) == 2)
    }

    @Test func 日のボタンの内容は日の見出しと選択日と選べるかを持ち表示月の変化で無効にならない() async {
        let viewModel = await Harness().loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        let items = viewModel.dayAccessibility(inWeek: week)
        let cells = viewModel.weekCells(at: week)

        #expect(items.map(\.label) == cells.map(\.accessibilityLabel))
        #expect(items.map(\.isSelected) == cells.map(\.isSelected))
        #expect(items.map(\.isSelectable) == cells.map(\.isSelectable))
        #expect(!isInvalidated(by: { viewModel.gridDidScroll(toTopWeek: week + 5) }, reading: { _ = viewModel.dayAccessibility(inWeek: week) }))
    }

    @Test func 列から日と見出しを求める() async {
        let viewModel = await Harness().loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3

        #expect(viewModel.day(inWeek: week, column: 4) == SampleData.day(2026, 10, 22))
        #expect(viewModel.dayHeader(inWeek: week, column: 4) == "10月22日(木)")
        #expect(viewModel.day(inWeek: week, column: 7) == nil)
        #expect(viewModel.day(inWeek: week, column: -1) == nil)
        #expect(viewModel.dayHeader(inWeek: week, column: 7) == "")
    }

    @Test func 予定の多いサンプルでも全週の配置が7列の中に収まる() async throws {
        let viewModel = await Harness(events: SampleData.denseMonthViewEvents).loadedPopover()
        for week in 0..<viewModel.weekCount {
            let layout = viewModel.monthWeekLayout(at: week)
            #expect(layout.items.allSatisfy { 0 <= $0.columns.lowerBound && $0.columns.upperBound <= 7 })
        }
        let busy = viewModel.monthWeekLayout(at: viewModel.displayedMonthFirstWeek + 3)
        #expect(!busy.items.isEmpty)
        #expect(busy.visible(laneCapacity: 4).hiddenCountByColumn.contains { $0 > 0 })
    }

    @Test func マス目の初期位置の週は表示月の最初の週と同じで表示月の変化で親を無効にしない() async {
        let viewModel = await Harness().loadedPopover()

        #expect(viewModel.initialGridWeek == viewModel.displayedMonthFirstWeek)
        #expect(!isInvalidated(by: { viewModel.showNextMonth() }, reading: { _ = viewModel.initialGridWeek }))
        #expect(viewModel.initialGridWeek == viewModel.displayedMonthFirstWeek)
    }
}
