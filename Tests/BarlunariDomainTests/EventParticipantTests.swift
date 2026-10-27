import Foundation
import Testing
@testable import BarlunariDomain

@Suite struct EventParticipantTests {
    @Test func 名前とメールアドレスの前後の空白を取り除く() throws {
        let participant = try EventParticipant(name: "  山田 太郎\n", emailAddress: " yamada@example.com ")
        #expect(participant.name == "山田 太郎")
        #expect(participant.emailAddress == "yamada@example.com")
    }

    @Test func 名前だけでも作れる() throws {
        let participant = try EventParticipant(name: "山田 太郎", emailAddress: nil)
        #expect(participant.emailAddress == nil)
        #expect(participant.displayName == "山田 太郎")
    }

    @Test func メールアドレスだけでも作れて表示名になる() throws {
        let participant = try EventParticipant(name: nil, emailAddress: "yamada@example.com")
        #expect(participant.name == nil)
        #expect(participant.displayName == "yamada@example.com")
    }

    @Test func 名前が空白だけならメールアドレスを表示名にする() throws {
        let participant = try EventParticipant(name: "  ", emailAddress: "yamada@example.com")
        #expect(participant.name == nil)
        #expect(participant.displayName == "yamada@example.com")
    }

    @Test(arguments: [(nil, nil), ("", ""), (" ", "\n"), (nil, " "), ("\t", nil)] as [(String?, String?)])
    func 名前もメールアドレスもなければ作れない(name: String?, email: String?) {
        #expect(throws: DomainError.participantWithoutNameOrEmail) {
            try EventParticipant(name: name, emailAddress: email)
        }
    }

    @Test func 既定は出欠の概念なしで主催者でも自分でもない() throws {
        let participant = try EventParticipant(name: "山田", emailAddress: nil)
        #expect(participant.attendance == .notApplicable)
        #expect(!participant.isOrganizer)
        #expect(!participant.isCurrentUser)
    }

    @Test func 出欠と主催者と自分を保持する() throws {
        let participant = try EventParticipant(
            name: "山田", emailAddress: nil, attendance: .tentative, isOrganizer: true, isCurrentUser: true
        )
        #expect(participant.attendance == .tentative)
        #expect(participant.isOrganizer)
        #expect(participant.isCurrentUser)
    }
}

@Suite struct CalendarEventDetailTests {
    private func event(notes: String?, participants: [EventParticipant] = []) throws -> CalendarEvent {
        try CalendarEvent(
            accountID: AccountID("a"), id: EventID("e"), calendarID: CalendarID("c"), title: "t",
            schedule: .timed(DateInterval(start: Date(timeIntervalSince1970: 0), duration: 60)),
            notes: notes, participants: participants
        )
    }

    @Test func メモの前後の空白を取り除く() throws {
        #expect(try event(notes: "\n 議題 \n").notes == "議題")
    }

    @Test(arguments: ["", "  \n\t"])
    func 空白だけのメモはnilにする(notes: String) throws {
        #expect(try event(notes: notes).notes == nil)
    }

    @Test func 参加者の順序を保つ() throws {
        let first = try EventParticipant(name: "A", emailAddress: nil)
        let second = try EventParticipant(name: "B", emailAddress: nil)
        #expect(try event(notes: nil, participants: [first, second]).participants == [first, second])
    }
}
