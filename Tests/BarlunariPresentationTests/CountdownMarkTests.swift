import Foundation
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

@MainActor
@Suite(.timeLimit(.minutes(1))) struct CountdownMarkTests {
    private func event(titled title: String) throws -> CalendarEvent {
        try #require(SampleData.events.first { $0.title == title })
    }

    @Test func 既定どおりの予定には記号を付けない() throws {
        let timed = try event(titled: "デザインレビュー")
        let allDay = try event(titled: "引っ越し")
        let settings = CountdownTargetSettings()
        #expect(CountdownMark(timed, policy: CountdownTargetPolicy(events: settings)) == .none)
        #expect(CountdownMark(allDay, policy: CountdownTargetPolicy(events: settings)) == .none)
    }

    @Test func 対象から外した時刻付きの予定には外した記号を付ける() throws {
        let timed = try event(titled: "デザインレビュー")
        var settings = CountdownTargetSettings()
        settings.set(timed.id, isTarget: false)
        #expect(CountdownMark(timed, policy: CountdownTargetPolicy(events: settings)) == .excluded)
        #expect(CountdownMark.excluded.symbolName == "clock.badge.xmark")
        #expect(CountdownMark.excluded.label == "残り時間の対象外")
    }

    @Test func 終日の予定は保存済みの選択があっても記号を付けない() throws {
        let allDay = try event(titled: "引っ越し")
        for isTarget in [true, false] {
            var settings = CountdownTargetSettings()
            settings.set(allDay.id, isTarget: isTarget)
            #expect(CountdownMark(allDay, policy: CountdownTargetPolicy(events: settings)) == .none)
        }
    }

    @Test func 含めた記号の見た目() {
        #expect(CountdownMark.included.symbolName == "clock.badge.checkmark")
        #expect(CountdownMark.included.label == "残り時間の対象")
    }

    @Test func 既定と同じ値を選び直した予定には記号を付けない() throws {
        let timed = try event(titled: "デザインレビュー")
        var settings = CountdownTargetSettings()
        settings.set(timed.id, isTarget: true)
        #expect(CountdownMark(timed, policy: CountdownTargetPolicy(events: settings)) == .none)
        #expect(CountdownMark.none.symbolName == nil)
        #expect(CountdownMark.none.label == nil)
    }

    @Test func 辞退した予定にも設定に従って記号を付ける() throws {
        let declined = try event(titled: "辞退した会議")
        var settings = CountdownTargetSettings()
        settings.set(declined.id, isTarget: false)
        #expect(CountdownMark(declined, policy: CountdownTargetPolicy(events: settings)) == .excluded)
    }

    @Test func カレンダーごと含めないカレンダーの予定には一律に記号を付けない() throws {
        let timed = try event(titled: "デザインレビュー")
        let allDay = try event(titled: "開発合宿")
        let policy = CountdownTargetPolicy(calendars: CountdownCalendarSettings(excludedCalendars: [timed.calendarIdentity]))
        #expect(!policy.isTarget(timed))
        #expect(CountdownMark(timed, policy: policy) == .none)
        #expect(CountdownMark(allDay, policy: policy) == .none)
    }

    @Test func 含めないカレンダーの予定を予定ごとに含めると含めた記号を付ける() throws {
        let timed = try event(titled: "デザインレビュー")
        var policy = CountdownTargetPolicy(calendars: CountdownCalendarSettings(excludedCalendars: [timed.calendarIdentity]))
        policy.choose(timed.id, isTarget: true)
        #expect(CountdownMark(timed, policy: policy) == .included)
        policy.choose(timed.id, isTarget: false)
        #expect(CountdownMark(timed, policy: policy) == .none)
    }

    @Test func 含めるカレンダーの時刻付きの予定を外すと外した記号を付ける() throws {
        let timed = try event(titled: "デザインレビュー")
        let other = try event(titled: "夕食")
        var policy = CountdownTargetPolicy(calendars: CountdownCalendarSettings(excludedCalendars: [other.calendarIdentity]))
        policy.choose(timed.id, isTarget: false)
        #expect(CountdownMark(timed, policy: policy) == .excluded)
    }

    @Test func 詳細で切り替えると日の欄と予定一覧と月のマス目の記号が更新される() async throws {
        let harness = Harness()
        let popover = await harness.loadedPopover()
        let week = popover.displayedMonthFirstWeek
        let row = try #require(popover.selectedSection.rows.first { $0.title == "デザインレビュー" })
        #expect(row.countdownMark == .none)
        let layoutBefore = popover.monthWeekLayout(at: week + 3)
        #expect(layoutBefore.items.first { $0.title == "デザインレビュー" }?.countdownMark == CountdownMark.none)

        popover.showDetail(of: row)
        await popover.setIncludedInCountdown(false)

        let updated = try #require(popover.selectedSection.rows.first { $0.title == "デザインレビュー" })
        #expect(updated.countdownMark == .excluded)
        #expect(updated.accessibilityLabel.hasSuffix("残り時間の対象外"))
        let block = try #require(popover.selectedDaySchedule.blocks.first { $0.item.title == "デザインレビュー" })
        #expect(block.item.countdownMark == .excluded)
        #expect(block.item.accessibilityLabel.hasSuffix("残り時間の対象外"))
        let layoutAfter = popover.monthWeekLayout(at: week + 3)
        #expect(layoutAfter.items.first { $0.title == "デザインレビュー" }?.countdownMark == .excluded)

        await popover.setIncludedInCountdown(true)
        let restored = try #require(popover.selectedSection.rows.first { $0.title == "デザインレビュー" })
        #expect(restored.countdownMark == CountdownMark.none)
    }

    @Test func 月のマス目の読み上げに残り時間の対象を付ける() {
        let event = MonthWeekLayoutTests.timed("review", "デザインレビュー", day: 3, hour: 10)
        let layout = MonthWeekLayoutTests.layout([event], countdownMark: { _ in .excluded })
        #expect(MonthWeekRowView.accessibilityLabel(of: layout.items[0]).hasSuffix("、残り時間の対象外"))
    }
}
