import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

@Suite struct CalendarCheckStateTests {
    @Test(arguments: [
        ([true, true], CalendarCheckState.all),
        ([false, false], .none),
        ([true, false], .mixed),
        ([false, true, true], .mixed),
        ([true], .all),
        ([false], .none),
        ([], .none),
    ] as [([Bool], CalendarCheckState)])
    func カレンダーの表示状態からアカウントのチェックの状態を求める(flags: [Bool], expected: CalendarCheckState) {
        #expect(CalendarCheckState(visibleFlags: flags) == expected)
    }

    @Test func 押したときの切り替え先はすべて表示のときだけ非表示で混在はすべて表示() {
        #expect(CalendarCheckState.all.nextIsVisible == false)
        #expect(CalendarCheckState.none.nextIsVisible == true)
        #expect(CalendarCheckState.mixed.nextIsVisible == true)
    }

    @Test func エスケープは詳細表示するカレンダーの順に閉じる() {
        #expect(PopoverEscapeAction.resolve(hasDetail: true, hasCalendarFilter: true) == .closeDetail)
        #expect(PopoverEscapeAction.resolve(hasDetail: false, hasCalendarFilter: true) == .closeCalendarFilter)
        #expect(PopoverEscapeAction.resolve(hasDetail: false, hasCalendarFilter: false) == .closePanel)
    }
}

@MainActor
@Suite struct CalendarFilterViewModelTests {
    let google = SampleData.googleAccount
    let work = SampleData.workAccount

    private func openedHarness(hidden: [UserCalendar] = []) async -> (Harness, CalendarPopoverViewModel) {
        let harness = Harness(hiddenCalendars: hidden)
        let popover = await harness.loadedPopover()
        popover.openCalendarFilter()
        await popover.waitForCalendarFilter()
        return (harness, popover)
    }

    @Test func 開くとアカウントごとにカレンダーと表示状態を読み込む() async {
        let (_, popover) = await openedHarness(hidden: [SampleData.holidayCalendar])
        #expect(popover.isCalendarFilterOpen)
        #expect(popover.calendarFilterPhase == .loaded)
        #expect(popover.calendarFilterSections.map(\.id) == [google.id, work.id])
        #expect(popover.calendarFilterSections[0].items.map(\.isVisible) == [true, false])
        #expect(popover.calendarFilterSections[0].checkState == .mixed)
        #expect(popover.calendarFilterSections[1].checkState == .all)
    }

    @Test func 許可がないときは一覧の代わりに案内の文を出す() async {
        let harness = Harness(status: .denied)
        harness.popover.openCalendarFilter()
        await harness.popover.waitForCalendarFilter()
        #expect(harness.popover.calendarFilterPhase == .unavailable(CalendarAccessGuide.denied.message))
    }

    @Test func 開くと詳細を閉じ_詳細を開くと一覧を閉じる() async throws {
        let harness = Harness()
        let popover = await harness.loadedPopover()
        let row = try #require(popover.selectedSection.rows.first)
        popover.showDetail(of: row)
        popover.openCalendarFilter()
        #expect(popover.eventDetail == nil)
        popover.showDetail(of: row)
        #expect(!popover.isCalendarFilterOpen)
        #expect(popover.eventDetail != nil)
    }

    @Test func 表示モードの切り替えと日の移動では閉じず_開き直したときに閉じる() async {
        let (_, popover) = await openedHarness()
        popover.setDisplayMode(.compact)
        popover.showNextMonth()
        popover.select(SampleData.day(2026, 11, 10))
        #expect(popover.isCalendarFilterOpen)
        popover.popoverDidAppear()
        #expect(!popover.isCalendarFilterOpen)
    }

    @Test func エスケープは一覧だけを閉じ_次でパネルを閉じる() async {
        let (_, popover) = await openedHarness()
        #expect(popover.performEscape() == .closeCalendarFilter)
        #expect(!popover.isCalendarFilterOpen)
        #expect(popover.performEscape() == .closePanel)
    }

    @Test func 続けて切り替えても一覧は開いたまま() async {
        let (_, popover) = await openedHarness()
        await popover.setVisibility(of: SampleData.holidayCalendar.id, isVisible: false)
        await popover.setVisibility(of: SampleData.personalCalendar.id, isVisible: false)
        #expect(popover.isCalendarFilterOpen)
        #expect(popover.calendarFilterSections[0].checkState == CalendarCheckState.none)
    }

    @Test func カレンダーの切り替えを保存し_予定を読み直し_設定画面に伝える() async {
        let (harness, popover) = await openedHarness()
        let before = popover.changeRevision
        #expect(popover.snapshot.calendars.contains { $0.id == SampleData.workCalendar.id })

        await popover.setVisibility(of: SampleData.workCalendar.id, isVisible: false)
        await popover.waitForLoad()

        #expect(await harness.visibility.load().hiddenCalendars == [SampleData.workCalendar.id])
        #expect(!popover.snapshot.calendars.contains { $0.id == SampleData.workCalendar.id })
        #expect(!popover.snapshot.days.flatMap(\.events).contains { $0.calendarID == SampleData.workCalendar.calendarID })
        #expect(popover.changeRevision == before + 1)
        // 自分の通知では読み込み直さない。
        let requests = await harness.eventRepository.requests.count
        popover.reloadIfChangedElsewhere()
        await popover.waitForLoad()
        #expect(await harness.eventRepository.requests.count == requests)

        await harness.settings.refreshIfChangedElsewhere()
        #expect(harness.settings.calendars.first { $0.id == SampleData.workCalendar.id }?.isVisible == false)
    }

    @Test func アカウントのまとめての切り替えはすべてのカレンダーを切り替える() async {
        let (harness, popover) = await openedHarness(hidden: [SampleData.holidayCalendar])
        #expect(popover.calendarFilterSections[0].checkState == .mixed)

        // 混在のときに押すと、すべて表示になる。
        await popover.setVisibility(ofAccount: google.id, isVisible: popover.calendarFilterSections[0].checkState.nextIsVisible)
        #expect(popover.calendarFilterSections[0].checkState == .all)
        #expect(await harness.visibility.load().hiddenCalendars.isEmpty)

        await popover.setVisibility(ofAccount: google.id, isVisible: popover.calendarFilterSections[0].checkState.nextIsVisible)
        #expect(popover.calendarFilterSections[0].checkState == CalendarCheckState.none)
        #expect(await harness.visibility.load().hiddenCalendars == [SampleData.personalCalendar.id, SampleData.holidayCalendar.id])
        // 他のアカウントは変わらない。
        #expect(popover.calendarFilterSections[1].checkState == .all)
    }

    @Test func 設定画面での変更をポップオーバーの一覧と予定に反映する() async {
        let (harness, popover) = await openedHarness()
        await harness.settings.load()
        await harness.settings.setVisibility(of: SampleData.workCalendar.id, isVisible: false)

        popover.reloadIfChangedElsewhere()
        await popover.waitForLoad()
        await popover.waitForCalendarFilter()

        #expect(popover.calendarFilterSections[1].items.first { $0.id == SampleData.workCalendar.id }?.isVisible == false)
        #expect(!popover.snapshot.calendars.contains { $0.id == SampleData.workCalendar.id })
    }

    @Test func 切り替えで予定が変わると月表示の記憶を捨てる() async {
        let (_, popover) = await openedHarness()
        let stamp = popover.monthLayoutStamp
        await popover.setVisibility(of: SampleData.workCalendar.id, isVisible: false)
        await popover.waitForLoad()
        #expect(popover.monthLayoutStamp.dataRevision != stamp.dataRevision)
        #expect(popover.monthImageStore.weekCount == 0)
    }

    @Test func 一覧の開閉と切り替えでは取得範囲を変えず_読み込むのは切り替えのときだけ() async {
        let (harness, popover) = await openedHarness()
        let requests = await harness.eventRepository.requests
        popover.closeCalendarFilter()
        popover.openCalendarFilter()
        await popover.waitForCalendarFilter()
        await popover.waitForLoad()
        #expect(await harness.eventRepository.requests == requests)

        await popover.setVisibility(of: SampleData.workCalendar.id, isVisible: false)
        await popover.waitForLoad()
        let after = await harness.eventRepository.requests
        #expect(after.count == requests.count + 1)
        #expect(after.last == requests.last)
    }
}
