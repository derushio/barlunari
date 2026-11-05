import Foundation
import Testing
@testable import BarlunariDomain

@Suite struct AttendanceResponseTests {
    func event(
        attendance: AttendanceStatus, participants: [EventParticipant] = []
    ) -> CalendarEvent {
        CalendarEvent(
            accountID: TestSupport.accountID("a"), id: TestSupport.eventID("e@0"), calendarID: TestSupport.calendarID("c"),
            title: "会議", schedule: .timed(DateInterval(start: TestSupport.date(2026, 10, 24, 10), duration: 3600)),
            participants: participants, attendance: attendance
        )
    }

    func participant(
        _ name: String, _ attendance: AttendanceStatus, organizer: Bool = false, me: Bool = false
    ) throws -> EventParticipant {
        try EventParticipant(name: name, emailAddress: nil, attendance: attendance, isOrganizer: organizer, isCurrentUser: me)
    }

    @Test(arguments: [
        (AttendanceResponse.accepted, AttendanceStatus.accepted),
        (.tentative, .tentative),
        (.declined, .declined),
    ] as [(AttendanceResponse, AttendanceStatus)])
    func 回答は対応する出欠になる(response: AttendanceResponse, expected: AttendanceStatus) {
        #expect(response.attendance == expected)
    }

    @Test func 回答は承諾と未定と辞退の3値だけ() {
        #expect(AttendanceResponse.allCases.count == 3)
    }

    @Test(arguments: [AttendanceStatus.accepted, .tentative, .declined, .needsAction])
    func 招待された予定は回答できる(attendance: AttendanceStatus) throws {
        let invited = event(attendance: attendance, participants: [
            try participant("主催者", .accepted, organizer: true), try participant("自分", attendance, me: true),
        ])
        #expect(invited.canRespond)
    }

    @Test func 出欠の概念がない予定は回答できない() {
        #expect(!event(attendance: .notApplicable).canRespond)
    }

    @Test func 自分が主催者の予定は回答できない() throws {
        let organized = event(attendance: .accepted, participants: [
            try participant("自分", .accepted, organizer: true, me: true), try participant("同僚", .needsAction),
        ])
        #expect(organized.isOrganizedByCurrentUser)
        #expect(!organized.canRespond)
    }

    @Test func 他の人が主催者でも自分は主催者ではない() throws {
        let invited = event(attendance: .needsAction, participants: [
            try participant("主催者", .accepted, organizer: true), try participant("自分", .needsAction, me: true),
        ])
        #expect(!invited.isOrganizedByCurrentUser)
    }

    @Test func 回答すると自分の出欠だけが変わる() throws {
        let invited = event(attendance: .needsAction, participants: [
            try participant("主催者", .accepted, organizer: true), try participant("自分", .needsAction, me: true),
            try participant("同僚", .needsAction),
        ])
        let declined = invited.responded(with: .declined)

        #expect(declined.attendance == .declined)
        #expect(declined.participants.map(\.attendance) == [.accepted, .declined, .needsAction])
        #expect(declined.id == invited.id)
        #expect(declined.title == invited.title)
        #expect(declined.canRespond)
    }
}
