import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

@MainActor
@Suite struct EventRSVPViewModelTests {
    /// 2026-10-28 の「新機能の企画会議」。自分は未回答で、主催者は別の人である。
    var invitation: CalendarEvent { SampleData.events.first { $0.title == "新機能の企画会議" }! }

    func openInvitation(_ harness: Harness) async -> CalendarPopoverViewModel {
        let viewModel = await harness.loadedPopover()
        viewModel.showDetail(of: invitation.id)
        return viewModel
    }

    /// 次の読み直しで、予定の取得結果を `events` にして読み込みを終える。
    func reload(_ harness: Harness, _ viewModel: CalendarPopoverViewModel, returning events: [CalendarEvent]) async {
        await harness.eventRepository.gate()
        let index = await harness.eventRepository.pendingCount
        viewModel.reload()
        while await harness.eventRepository.pendingCount < index + 1 { await Task.yield() }
        await harness.eventRepository.resume(at: index, events: events)
        await viewModel.waitForLoad()
    }

    func events(replacing event: CalendarEvent, with replacement: CalendarEvent) -> [CalendarEvent] {
        SampleData.events.map { $0.id == event.id ? replacement : $0 }
    }

    // MARK: - 回答欄を出す条件

    @Test func 招待された予定の詳細に回答欄を出す() async throws {
        let viewModel = await openInvitation(Harness())

        let rsvp = try #require(viewModel.eventDetail?.rsvp)
        #expect(rsvp.current == .needsAction)
        #expect(!rsvp.isResponding)
        #expect(rsvp.errorMessage == nil)
    }

    @Test func 出欠の概念がない予定には回答欄を出さない() async throws {
        let viewModel = await Harness().loadedPopover()
        let movingDay = try #require(SampleData.events.first { $0.title == "引っ越し" })
        viewModel.showDetail(of: movingDay.id)

        #expect(viewModel.eventDetail != nil)
        #expect(viewModel.eventDetail?.rsvp == nil)
    }

    @Test func 自分が主催者の予定には回答欄を出さない() async throws {
        let me = try EventParticipant(name: "自分", emailAddress: nil, attendance: .accepted, isOrganizer: true, isCurrentUser: true)
        let own = CalendarEvent(
            accountID: invitation.accountID, id: try EventID("own@0"), calendarID: invitation.calendarID, title: "自分の会議",
            schedule: invitation.schedule, participants: [me], attendance: .accepted
        )
        let viewModel = await Harness(events: [own]).loadedPopover()
        viewModel.showDetail(of: own.id)

        #expect(viewModel.eventDetail?.rsvp == nil)
        #expect(viewModel.eventDetail?.attendanceText == "承諾")
    }

    // MARK: - 回答

    @Test func 回答すると出欠を保存し詳細の出欠を新しい値にする() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)

        await viewModel.respond(.tentative)

        #expect(harness.responder.responses == [.init(event: invitation.id, response: .tentative)])
        let detail = try #require(viewModel.eventDetail)
        #expect(detail.rsvp?.current == .tentative)
        #expect(detail.attendanceText == "未定")
        #expect(detail.participants.first { $0.isCurrentUser }?.attendance == .tentative)
        #expect(viewModel.rsvpPhase == .idle)
    }

    @Test func 回答しても詳細は閉じず日と月は変わらない() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        let day = viewModel.selectedDay
        let month = viewModel.displayedMonth

        await viewModel.respond(.accepted)

        #expect(viewModel.detailEventID == invitation.id)
        #expect(viewModel.selectedDay == day)
        #expect(viewModel.displayedMonth == month)
    }

    @Test func 保存中は二重に送らずボタンを無効にする() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        harness.responder.hold()

        let first = Task { await viewModel.respond(.declined) }
        await waitUntil { viewModel.rsvpPhase == .responding(.declined) && harness.responder.attemptCount == 1 }
        #expect(viewModel.eventDetail?.rsvp?.isResponding == true)
        #expect(viewModel.eventDetail?.rsvp?.responding == .declined)

        await viewModel.respond(.accepted)
        await viewModel.respond(.declined)
        #expect(harness.responder.attemptCount == 1)

        harness.responder.release()
        await first.value
        #expect(harness.responder.responses == [.init(event: invitation.id, response: .declined)])
        #expect(viewModel.rsvpPhase == .idle)
        #expect(viewModel.eventDetail?.rsvp?.current == .declined)
    }

    @Test func すでにその出欠のときは保存しない() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.accepted)

        await viewModel.respond(.accepted)

        #expect(harness.responder.attemptCount == 1)
    }

    @Test func 回答できない予定では何もしない() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.showDetail(of: try #require(SampleData.events.first { $0.title == "引っ越し" }).id)

        await viewModel.respond(.declined)

        #expect(harness.responder.attemptCount == 0)
    }

    @Test func 詳細を開いていなければ何もしない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()

        await viewModel.respond(.declined)

        #expect(harness.responder.attemptCount == 0)
    }

    // MARK: - 失敗

    @Test(arguments: [
        (EventResponseError.unsupported, "この macOS では、このアプリから出欠を回答できません。カレンダーで回答してください。"),
        (.saveFailed, "回答を保存できませんでした。このカレンダーのアカウントが、出欠の変更を許可していない可能性があります。カレンダーで回答してください。"),
        (.eventNotFound, "予定が見つかりませんでした。カレンダーで予定を開いて確認してください。"),
    ] as [(EventResponseError, String)])
    func 失敗したら理由を詳細に出し出欠は変えない(error: EventResponseError, message: String) async throws {
        let harness = Harness(responder: FakeEventResponder(failure: error))
        let viewModel = await openInvitation(harness)

        await viewModel.respond(.accepted)

        let rsvp = try #require(viewModel.eventDetail?.rsvp)
        #expect(rsvp.errorMessage == message)
        #expect(rsvp.current == .needsAction)
        #expect(!rsvp.isResponding)
        #expect(harness.responder.responses.isEmpty)
    }

    @Test func アクセスの失敗は許可の案内の文にする() async throws {
        let harness = Harness(responder: FakeEventResponder(failure: CalendarAccessError.denied))
        let viewModel = await openInvitation(harness)

        await viewModel.respond(.accepted)

        #expect(viewModel.eventDetail?.rsvp?.errorMessage == CalendarAccessGuide.denied.message)
    }

    @Test func 失敗のあとにもう一度回答できる() async throws {
        let harness = Harness(responder: FakeEventResponder(failure: EventResponseError.saveFailed))
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.accepted)
        harness.responder.setFailure(nil)

        await viewModel.respond(.accepted)

        #expect(viewModel.eventDetail?.rsvp?.errorMessage == nil)
        #expect(viewModel.eventDetail?.rsvp?.current == .accepted)
    }

    @Test func 失敗したらカレンダーで予定を開ける() async throws {
        let harness = Harness(responder: FakeEventResponder(failure: EventResponseError.saveFailed))
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.accepted)

        await viewModel.openDetailInCalendarApp()

        #expect(harness.calendarAppOpener.openedEvents == [invitation.id])
        #expect(viewModel.eventDetail?.rsvp?.errorMessage != nil)
    }

    @Test func カレンダーで開けなかったら理由を出す() async throws {
        let harness = Harness(calendarAppOpener: FakeCalendarAppOpener(result: false))
        let viewModel = await openInvitation(harness)

        await viewModel.openDetailInCalendarApp()

        #expect(viewModel.eventDetail?.rsvp?.errorMessage == "カレンダーで予定を開けませんでした。カレンダーを開いて、予定を探してください。")
    }

    @Test func 詳細を閉じると失敗の表示は消える() async throws {
        let harness = Harness(responder: FakeEventResponder(failure: EventResponseError.saveFailed))
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.accepted)

        viewModel.closeDetail()
        viewModel.showDetail(of: invitation.id)

        #expect(viewModel.rsvpPhase == .idle)
        #expect(viewModel.eventDetail?.rsvp?.errorMessage == nil)
    }

    // MARK: - 辞退したあと

    @Test func 辞退して一覧から除かれても詳細を出し続ける() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.declined)

        // 保存後の変更通知で読み直すと、辞退した予定は AgendaBuilder が一覧から除く。
        await reload(harness, viewModel, returning: events(replacing: invitation, with: invitation.responded(with: .declined)))

        #expect(viewModel.selectedDaySchedule.blocks.allSatisfy { $0.id != invitation.id })
        #expect(viewModel.detailEventID == invitation.id)
        let detail = try #require(viewModel.eventDetail)
        #expect(detail.title == "新機能の企画会議")
        #expect(detail.rsvp?.current == .declined)
        #expect(detail.attendanceText == "辞退")
    }

    @Test func 辞退を承諾で取り消せる() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.declined)
        await reload(harness, viewModel, returning: events(replacing: invitation, with: invitation.responded(with: .declined)))

        await viewModel.respond(.accepted)
        await reload(harness, viewModel, returning: events(replacing: invitation, with: invitation.responded(with: .accepted)))

        #expect(harness.responder.responses.map(\.response) == [.declined, .accepted])
        #expect(viewModel.detailEventID == invitation.id)
        #expect(viewModel.eventDetail?.rsvp?.current == .accepted)
    }

    @Test func 辞退したあと詳細を閉じたら詳細は戻らない() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.declined)
        await reload(harness, viewModel, returning: events(replacing: invitation, with: invitation.responded(with: .declined)))

        viewModel.closeDetail()
        viewModel.showDetail(of: invitation.id)

        #expect(viewModel.eventDetail == nil)
    }

    @Test func 辞退以外で回答した予定が読み直しで消えたら一覧に戻る() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.tentative)

        await reload(harness, viewModel, returning: SampleData.events.filter { $0.id != invitation.id })

        #expect(viewModel.detailEventID == nil)
        #expect(viewModel.eventDetail == nil)
    }

    @Test func 読み直した予定の出欠が回答と同じになったら一覧の予定に任せる() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.tentative)
        let renamed = CalendarEvent(
            accountID: invitation.accountID, id: invitation.eventID, calendarID: invitation.calendarID,
            title: "新機能の企画会議（変更）", schedule: invitation.schedule, attendance: .tentative
        )

        await reload(harness, viewModel, returning: events(replacing: invitation, with: renamed))

        #expect(viewModel.eventDetail?.title == "新機能の企画会議（変更）")
    }

    @Test func 辞退のあと別の場所で承諾に戻されて予定が一覧に戻ったら詳細は新しい内容になる() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        await viewModel.respond(.declined)
        await reload(harness, viewModel, returning: events(replacing: invitation, with: invitation.responded(with: .declined)))
        let renamed = CalendarEvent(
            accountID: invitation.accountID, id: invitation.eventID, calendarID: invitation.calendarID,
            title: "新機能の企画会議（カレンダーで変更）", schedule: invitation.schedule, attendance: .accepted
        )

        // カレンダー.app で承諾に戻されると、予定が一覧に戻る。
        await reload(harness, viewModel, returning: events(replacing: invitation, with: renamed))

        #expect(viewModel.eventDetail?.title == "新機能の企画会議（カレンダーで変更）")
        #expect(viewModel.eventDetail?.rsvp?.current == .accepted)
    }

    @Test func 保存の前に始まった読み込みの結果では回答した値を捨てない() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        await harness.eventRepository.gate()
        let index = await harness.eventRepository.pendingCount
        viewModel.reload()
        while await harness.eventRepository.pendingCount < index + 1 { await Task.yield() }

        await viewModel.respond(.tentative)
        // 保存の前に始まった読み込みは、保存前の出欠（未回答）の予定を返す。
        await harness.eventRepository.resume(at: index, events: SampleData.events)
        await viewModel.waitForLoad()

        #expect(viewModel.eventDetail?.rsvp?.current == .tentative)
    }

    @Test func 保存の直後の読み直しが先に反映されても辞退後の詳細は閉じない() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        harness.responder.hold()

        let responding = Task { await viewModel.respond(.declined) }
        await waitUntil { viewModel.rsvpPhase == .responding(.declined) && harness.responder.attemptCount == 1 }
        // 保存が起こした変更通知の読み直しが、respond の完了より先に反映される。
        await reload(harness, viewModel, returning: events(replacing: invitation, with: invitation.responded(with: .declined)))
        #expect(viewModel.detailEventID == invitation.id)

        harness.responder.release()
        await responding.value

        #expect(viewModel.detailEventID == invitation.id)
        #expect(viewModel.eventDetail?.rsvp?.current == .declined)
    }

    @Test func 保存に失敗して予定が消えていたら失敗の後に一覧に戻る() async throws {
        let harness = Harness(responder: FakeEventResponder(failure: EventResponseError.eventNotFound))
        let viewModel = await openInvitation(harness)
        harness.responder.hold()

        let responding = Task { await viewModel.respond(.accepted) }
        await waitUntil { viewModel.rsvpPhase == .responding(.accepted) && harness.responder.attemptCount == 1 }
        await reload(harness, viewModel, returning: SampleData.events.filter { $0.id != invitation.id })
        #expect(viewModel.detailEventID == invitation.id)

        harness.responder.release()
        await responding.value

        #expect(viewModel.detailEventID == nil)
    }

    // MARK: - 変更通知

    @Test func 変更通知による読み直しは回答の前後で増えない() async throws {
        let harness = Harness()
        let viewModel = await openInvitation(harness)
        let before = await harness.eventRepository.requests.count

        await viewModel.respond(.accepted)

        // 回答自体は読み直しを起こさない。読み直しは EventKit の変更通知が起こす。
        #expect(await harness.eventRepository.requests.count == before)
    }
}
