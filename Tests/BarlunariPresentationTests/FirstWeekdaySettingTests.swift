import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Synchronization
import Testing

@testable import BarlunariPresentation

/// 設定の「週の始まり」の保存と、それがポップオーバーの曜日の見出し・マス目・一覧に反映されること。
@MainActor
@Suite struct FirstWeekdaySettingTests {
    static let sundayFirst = ["日", "月", "火", "水", "木", "金", "土"]
    static let mondayFirst = ["月", "火", "水", "木", "金", "土", "日"]

    /// 日の曜日（1 が日曜、7 が土曜）。
    func weekday(of day: CalendarDay?) -> Int? {
        day.map { SampleData.calendar.component(.weekday, from: $0.startDate(in: SampleData.calendar)) }
    }

    /// 設定画面での変更を、ポップオーバーの View と同じ流れ（`changeRevision` の変化 → `reloadIfChangedElsewhere`）で反映する。
    func applyChange(_ viewModel: CalendarPopoverViewModel) async {
        viewModel.reloadIfChangedElsewhere()
        await viewModel.waitForLoad()
    }

    /// `read` が読んだ値が、`change` のあとに変わったと通知されたか。
    func isInvalidated(by change: () -> Void, reading read: () -> Void) -> Bool {
        let changed = Mutex(false)
        withObservationTracking {
            read()
        } onChange: {
            changed.withLock { $0 = true }
        }
        change()
        return changed.withLock { $0 }
    }

    // MARK: - SettingsViewModel

    @Test func 保存がなければシステムの設定に従う() async {
        let harness = Harness()
        await harness.settings.load()
        #expect(harness.settings.firstWeekday == nil)
    }

    @Test func 保存した曜日を読み込む() async {
        let harness = Harness(firstWeekday: .wednesday)
        await harness.settings.load()
        #expect(harness.settings.firstWeekday == .wednesday)
    }

    @Test func 曜日を選ぶと保存して変更を通知する() async {
        let harness = Harness()
        await harness.settings.load()
        let before = harness.notifier.revision

        harness.settings.setFirstWeekday(.monday)

        #expect(harness.settings.firstWeekday == .monday)
        #expect(harness.firstWeekdayStore.load() == .monday)
        #expect(harness.firstWeekdayStore.savedValues == [.monday])
        #expect(harness.notifier.revision == before + 1)
    }

    @Test func システムの設定に従うに戻すと保存を消して変更を通知する() async {
        let harness = Harness(firstWeekday: .monday)
        await harness.settings.load()
        let before = harness.notifier.revision

        harness.settings.setFirstWeekday(nil)

        #expect(harness.settings.firstWeekday == nil)
        #expect(harness.firstWeekdayStore.load() == nil)
        #expect(harness.firstWeekdayStore.savedValues.count == 1)
        #expect(harness.notifier.revision == before + 1)
    }

    @Test func 同じ値を選び直しても保存も通知もしない() async {
        let harness = Harness(firstWeekday: .monday)
        await harness.settings.load()
        let before = harness.notifier.revision

        harness.settings.setFirstWeekday(.monday)

        #expect(harness.firstWeekdayStore.savedValues.isEmpty)
        #expect(harness.notifier.revision == before)
    }

    @Test(arguments: Weekday.allCases) func 設定の選択肢の名前は日本語の曜日である(weekday: Weekday) {
        #expect(weekday.displayName == ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"][weekday.rawValue - 1])
    }

    // MARK: - ポップオーバーへの反映

    @Test func 保存した曜日があれば最初から月曜始まりで並ぶ() async {
        let viewModel = await Harness(firstWeekday: .monday).loadedPopover()
        #expect(viewModel.weekdaySymbols == Self.mondayFirst)
        #expect(weekday(of: viewModel.weekCells(at: viewModel.displayedMonthFirstWeek).first?.day) == 2)
    }

    @Test func 週の始まりを変えると曜日の見出しが作り直される() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        await harness.settings.load()
        #expect(viewModel.weekdaySymbols == Self.sundayFirst)

        harness.settings.setFirstWeekday(.monday)
        await applyChange(viewModel)

        #expect(viewModel.weekdaySymbols == Self.mondayFirst)
    }

    @Test func 曜日の見出しは週の始まりの変更で無効になる() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()

        #expect(isInvalidated(by: {
            harness.settings.setFirstWeekday(.thursday)
            viewModel.reloadIfChangedElsewhere()
        }, reading: { _ = viewModel.weekdaySymbols }))
        #expect(viewModel.weekdaySymbols == ["木", "金", "土", "日", "月", "火", "水"])
    }

    @Test func 週の始まりを変えると週の並びとマス目の曜日の種類が新しい開始曜日に従う() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 2
        #expect(viewModel.monthWeekDays(at: week).map(\.weekdayKind) == [.sunday, .weekday, .weekday, .weekday, .weekday, .weekday, .saturday])

        harness.settings.setFirstWeekday(.monday)
        await applyChange(viewModel)

        let week2 = viewModel.displayedMonthFirstWeek + 2
        let days = viewModel.monthWeekDays(at: week2)
        #expect(days.map(\.weekdayKind) == [.weekday, .weekday, .weekday, .weekday, .weekday, .saturday, .sunday])
        #expect(viewModel.weekCells(at: week2).map(\.weekdayKind) == days.map(\.weekdayKind))
        #expect(weekday(of: days.first?.day) == 2)
        #expect(weekday(of: viewModel.weekCells(at: viewModel.displayedMonthFirstWeek).first?.day) == 2)
    }

    @Test func 週の始まりを変えても選択日と表示月は保たれマス目と一覧の位置を合わせ直す() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.select(SampleData.day(2026, 10, 20))
        let selected = viewModel.selectedDay
        let month = viewModel.displayedMonth
        let gridSerial = viewModel.gridScrollRequest?.serial
        let agendaSerial = viewModel.agendaScrollRequest?.serial

        harness.settings.setFirstWeekday(.monday)
        await applyChange(viewModel)

        #expect(viewModel.selectedDay == selected)
        #expect(viewModel.displayedMonth == month)
        #expect(viewModel.gridScrollRequest?.serial != gridSerial)
        #expect(viewModel.agendaScrollRequest?.serial != agendaSerial)
        let week = viewModel.displayedMonthFirstWeek
        #expect(weekday(of: viewModel.weekCells(at: week).first?.day) == 2)
        // 選択日は、新しい週の並びの中で、選択日のある週の列に見つかる。
        let columns = (0..<viewModel.weekCount).compactMap { viewModel.selectedColumn(inWeek: $0) }
        #expect(columns.count == 1)
    }

    @Test func 週の始まりをシステムの設定に従うに戻すとシステムの値に従う() async {
        let harness = Harness(firstWeekday: .monday)
        let viewModel = await harness.loadedPopover()
        await harness.settings.load()
        #expect(viewModel.weekdaySymbols == Self.mondayFirst)

        harness.settings.setFirstWeekday(nil)
        await applyChange(viewModel)

        #expect(viewModel.weekdaySymbols == Self.sundayFirst)
    }

    @Test func 曜日を選んだあとはシステムの週の開始曜日が変わっても影響を受けない() async {
        let harness = Harness(firstWeekday: .friday)
        let viewModel = await harness.loadedPopover()
        var monday = SampleData.calendar
        monday.firstWeekday = 2

        harness.dateProvider.set(calendar: monday)
        harness.notificationCenter.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        await waitUntil { viewModel.weekdaySymbols == ["金", "土", "日", "月", "火", "水", "木"] }
        await viewModel.waitForLoad()

        #expect(viewModel.weekdaySymbols == ["金", "土", "日", "月", "火", "水", "木"])
    }

    @Test func システムの設定に従うときはシステムの週の開始曜日の変更に追従する() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        var monday = SampleData.calendar
        monday.firstWeekday = 2

        harness.dateProvider.set(calendar: monday)
        viewModel.systemCalendarDidChange()

        #expect(viewModel.weekdaySymbols == Self.mondayFirst)
    }

    @Test func 週の始まりが変わらない設定の変更では位置を合わせ直さず予定だけ読み直す() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        await harness.settings.load()
        let gridSerial = viewModel.gridScrollRequest?.serial
        let agendaSerial = viewModel.agendaScrollRequest?.serial
        let fetches = await harness.eventRepository.requests.count

        #expect(!isInvalidated(by: {
            harness.settings.setShowDeclinedEvents(false)
            viewModel.reloadIfChangedElsewhere()
        }, reading: { _ = viewModel.weekdaySymbols }))
        await viewModel.waitForLoad()

        #expect(viewModel.gridScrollRequest?.serial == gridSerial)
        #expect(viewModel.agendaScrollRequest?.serial == agendaSerial)
        #expect(await harness.eventRepository.requests.count > fetches)
    }

    @Test func 週の始まりが変わらない設定の変更では見出しと週の並びを作り直さない() async {
        let harness = Harness(firstWeekday: .monday)
        let viewModel = await harness.loadedPopover()
        await harness.settings.load()
        let week = viewModel.displayedMonthFirstWeek + 3

        #expect(!isInvalidated(by: {
            harness.settings.setShowDeclinedEvents(false)
            viewModel.reloadIfChangedElsewhere()
        }, reading: { _ = viewModel.outOfMonthColumns(inWeek: week) }))
    }

    @Test func 閉じている間に週の始まりが変わっても次に開いたとき新しい並びで出る() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        await harness.settings.load()
        let gridSerial = viewModel.gridScrollRequest?.serial

        // 変更の通知（`onChange`）を受けずに、保存だけが変わった状態にする。
        harness.firstWeekdayStore.save(.tuesday)
        viewModel.popoverDidAppear()
        await viewModel.waitForLoad()

        #expect(viewModel.weekdaySymbols == ["火", "水", "木", "金", "土", "日", "月"])
        #expect(viewModel.gridScrollRequest?.serial != gridSerial)
        #expect(weekday(of: viewModel.weekCells(at: viewModel.displayedMonthFirstWeek).first?.day) == 3)
    }

    @Test func 土曜始まりでも日曜と土曜の色の種類は列から正しく決まる() async {
        let viewModel = await Harness(firstWeekday: .saturday).loadedPopover()
        let days = viewModel.monthWeekDays(at: viewModel.displayedMonthFirstWeek + 2)
        #expect(days.map(\.weekdayKind) == [.saturday, .sunday, .weekday, .weekday, .weekday, .weekday, .weekday])
    }

    @Test func 予定の一覧の曜日も新しい週の開始曜日に従う() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let day = SampleData.day(2026, 10, 24)

        harness.settings.setFirstWeekday(.monday)
        await applyChange(viewModel)

        // 一覧は日ごとのセクションで、週の開始曜日が変わっても同じ日に同じ予定が並ぶ。
        #expect(viewModel.section(of: day).rows.map(\.title) == ["朝会", "デザインレビュー", "辞退した会議", "夕食"])
    }
}
