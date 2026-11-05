import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

/// 設定の「辞退した予定を表示」が、開いているポップオーバーの一覧・日の欄・月のマス目に反映されること。
@MainActor
@Suite struct ShowDeclinedEventsTests {
    let oct24 = SampleData.day(2026, 10, 24)

    /// 2026-10-28 の「新機能の企画会議」。自分は未回答で、主催者は別の人である。
    var invitation: CalendarEvent { SampleData.events.first { $0.title == "新機能の企画会議" }! }

    func titles(_ viewModel: CalendarPopoverViewModel, on day: CalendarDay) -> [String] {
        viewModel.sections(from: day, count: 1)[0].rows.map(\.title)
    }

    /// 設定画面での変更を、ポップオーバーの View と同じ流れ（`changeRevision` の変化 → `reloadIfChangedElsewhere`）で反映する。
    func applyChange(_ harness: Harness, _ viewModel: CalendarPopoverViewModel) async {
        viewModel.reloadIfChangedElsewhere()
        await viewModel.waitForLoad()
    }

    @Test func 設定をオフにして通知すると読み直して辞退した予定が一覧から消える() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        await harness.settings.load()
        #expect(titles(viewModel, on: oct24) == ["朝会", "デザインレビュー", "辞退した会議", "夕食"])

        harness.settings.setShowDeclinedEvents(false)
        await applyChange(harness, viewModel)

        #expect(titles(viewModel, on: oct24) == ["朝会", "デザインレビュー", "夕食"])
    }

    @Test func 設定をオンに戻して通知すると辞退した予定が一覧に戻る() async {
        let harness = Harness(showDeclinedEvents: false)
        let viewModel = await harness.loadedPopover()
        await harness.settings.load()
        #expect(titles(viewModel, on: oct24) == ["朝会", "デザインレビュー", "夕食"])

        harness.settings.setShowDeclinedEvents(true)
        await applyChange(harness, viewModel)

        #expect(titles(viewModel, on: oct24) == ["朝会", "デザインレビュー", "辞退した会議", "夕食"])
    }

    @Test func オフのとき日の欄の選択日の予定からも辞退した予定が消える() async {
        let harness = Harness(showDeclinedEvents: false)
        let viewModel = await harness.loadedPopover()

        viewModel.showSchedule(of: oct24)

        let schedule = viewModel.selectedDaySchedule
        #expect(!schedule.blocks.contains { $0.item.title == "辞退した会議" })
        #expect(schedule.blocks.count == 3)
    }

    @Test func オフのまま詳細から辞退しても詳細は閉じない() async throws {
        let harness = Harness(showDeclinedEvents: false)
        let viewModel = await harness.loadedPopover()
        viewModel.showDetail(of: invitation.id)
        await viewModel.respond(.declined)

        // 保存後の変更通知で読み直す。辞退した予定は設定により一覧から除かれる。
        await harness.eventRepository.gate()
        let index = await harness.eventRepository.pendingCount
        viewModel.reload()
        while await harness.eventRepository.pendingCount < index + 1 { await Task.yield() }
        await harness.eventRepository.resume(
            at: index, events: SampleData.events.map { $0.id == invitation.id ? invitation.responded(with: .declined) : $0 }
        )
        await viewModel.waitForLoad()

        #expect(titles(viewModel, on: SampleData.day(2026, 10, 28)).allSatisfy { $0 != "新機能の企画会議" })
        #expect(viewModel.detailEventID == invitation.id)
        let detail = try #require(viewModel.eventDetail)
        #expect(detail.title == "新機能の企画会議")
        #expect(detail.rsvp?.current == .declined)
    }

    @Test func 月のマス目の色の点は辞退した予定の表示に関わらず辞退だけの日につかない() async {
        for show in [true, false] {
            let harness = Harness(
                events: [SampleData.events.first { $0.title == "辞退した会議" }!], showDeclinedEvents: show
            )
            let viewModel = await harness.loadedPopover()
            #expect(viewModel.snapshot.colorsByDay[oct24] == nil)
        }
    }
}
