import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@Suite struct EventResponseUseCaseTests {
    func invited(attendance: AttendanceStatus = .needsAction) -> CalendarEvent {
        Fixtures.event("invite@0", calendar: "work", hour: 10, attendance: attendance)
    }

    @Test func 回答できる予定は出欠を変更する() async throws {
        let responder = FakeEventResponder()
        let event = invited()

        try await RespondToEventUseCase(responder: responder).execute(event: event, response: .tentative)

        #expect(responder.responses == [.init(event: event.id, response: .tentative)])
    }

    @Test func 出欠の概念がない予定は書き込まずに失敗する() async throws {
        let responder = FakeEventResponder()

        await #expect(throws: EventResponseError.notRespondable) {
            try await RespondToEventUseCase(responder: responder).execute(
                event: invited(attendance: .notApplicable), response: .accepted
            )
        }
        #expect(responder.attemptCount == 0)
    }

    @Test func 主催者の予定は書き込まずに失敗する() async throws {
        let organizer = try EventParticipant(
            name: "自分", emailAddress: nil, attendance: .accepted, isOrganizer: true, isCurrentUser: true
        )
        let event = CalendarEvent(
            accountID: Fixtures.accountA.id, id: try EventID("own@0"), calendarID: Fixtures.calendarID("work"), title: "自分の会議",
            schedule: .timed(DateInterval(start: Fixtures.date(2026, 10, 24, 10), duration: 3600)),
            participants: [organizer], attendance: .accepted
        )
        let responder = FakeEventResponder()

        await #expect(throws: EventResponseError.notRespondable) {
            try await RespondToEventUseCase(responder: responder).execute(event: event, response: .declined)
        }
        #expect(responder.attemptCount == 0)
    }

    @Test func ポートの失敗はそのまま伝える() async throws {
        let responder = FakeEventResponder(failure: EventResponseError.saveFailed)

        await #expect(throws: EventResponseError.saveFailed) {
            try await RespondToEventUseCase(responder: responder).execute(event: invited(), response: .accepted)
        }
        #expect(responder.responses.isEmpty)
    }

    @Test func カレンダーアプリで予定を開く() async {
        let opener = FakeCalendarAppOpener()
        let event = invited()

        let opened = await OpenEventInCalendarAppUseCase(opener: opener).execute(event.id)

        #expect(opened)
        #expect(opener.openedEvents == [event.id])
    }

    @Test func 開けなかったら失敗を返す() async {
        let opener = FakeCalendarAppOpener(result: false)
        #expect(await OpenEventInCalendarAppUseCase(opener: opener).execute(invited().id) == false)
    }
}
