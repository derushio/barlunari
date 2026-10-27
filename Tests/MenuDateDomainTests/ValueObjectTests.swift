import Foundation
import Testing
@testable import MenuDateDomain

@Suite struct IdentifierTests {
    @Test(arguments: ["", " ", "\n\t"])
    func rejectsBlankIdentifiers(value: String) {
        #expect(throws: DomainError.emptyIdentifier) { try CalendarID(value) }
        #expect(throws: DomainError.emptyIdentifier) { try EventID(value) }
        #expect(throws: DomainError.emptyIdentifier) { try AccountID(value) }
    }

    @Test func keepsRawValue() throws {
        #expect(try CalendarID("a@example.com").rawValue == "a@example.com")
        #expect(try EventID("evt_1") == EventID("evt_1"))
    }
}

@Suite struct CalendarColorTests {
    @Test func parsesAndNormalizesHex() throws {
        let color = try CalendarColor(hex: "#a1b2C3")
        #expect(color.red == 0xA1 && color.green == 0xB2 && color.blue == 0xC3)
        #expect(color.hexString == "#A1B2C3")
        #expect(CalendarColor(red: 0, green: 0, blue: 0).hexString == "#000000")
    }

    @Test(arguments: ["", "#FFF", "FFFFFF", "#GGGGGG", "#12345", "#1234567", " #123456", "#12 456"])
    func rejectsInvalidFormat(value: String) {
        #expect(throws: DomainError.invalidColor(value)) { try CalendarColor(hex: value) }
    }
}

@Suite struct UserAccountTests {
    @Test func trimsName() throws {
        let account = try UserAccount(id: TestSupport.accountID("1"), name: "  Google\n")
        #expect(account.name == "Google")
    }

    @Test(arguments: ["", " ", "\n\t"])
    func rejectsBlankName(value: String) {
        #expect(throws: DomainError.emptyAccountName) {
            try UserAccount(id: TestSupport.accountID("1"), name: value)
        }
    }

    @Test func isIdentifiedByID() throws {
        let first = try UserAccount(id: TestSupport.accountID("1"), name: "Google")
        let renamed = try UserAccount(id: TestSupport.accountID("1"), name: "仕事")
        #expect(first == renamed)
        #expect(first != (try UserAccount(id: TestSupport.accountID("2"), name: "Google")))
    }
}

@Suite struct EntityIdentityTests {
    let accountA = TestSupport.accountID("a")
    let accountB = TestSupport.accountID("b")

    @Test func userCalendarIsIdentifiedByAccountAndCalendarID() throws {
        let id = TestSupport.calendarID("a")
        let first = UserCalendar(accountID: accountA, id: id, name: "A", color: try CalendarColor(hex: "#112233"))
        let renamed = UserCalendar(accountID: accountA, id: id, name: "B", color: try CalendarColor(hex: "#445566"))
        #expect(first == renamed)
        #expect(first != UserCalendar(accountID: accountA, id: TestSupport.calendarID("b"), name: "A", color: first.color))
        // 同じ CalendarID でも、アカウントが違えば別のカレンダーである。
        #expect(first != UserCalendar(accountID: accountB, id: id, name: "A", color: first.color))
    }

    @Test func eventIsIdentifiedByAccountCalendarAndEventID() {
        func event(account: AccountID? = nil, calendar: String, id: String, title: String) -> CalendarEvent {
            CalendarEvent(
                accountID: account ?? accountA,
                id: TestSupport.eventID(id), calendarID: TestSupport.calendarID(calendar), title: title,
                schedule: .allDay(TestSupport.range(TestSupport.day(2026, 10, 24), days: 1)),
                iCalendarUID: "uid-1"
            )
        }
        #expect(event(calendar: "a", id: "1", title: "x") == event(calendar: "a", id: "1", title: "y"))
        #expect(event(calendar: "a", id: "1", title: "x") != event(calendar: "b", id: "1", title: "x"))
        #expect(event(calendar: "a", id: "1", title: "x") != event(calendar: "a", id: "2", title: "x"))
        #expect(event(calendar: "a", id: "1", title: "x") != event(account: accountB, calendar: "a", id: "1", title: "x"))
        // 共有キーは UID と日時で決まり、アカウント・カレンダー・予定 ID には左右されない。
        #expect(event(calendar: "a", id: "1", title: "x").sharedKey == event(account: accountB, calendar: "b", id: "2", title: "x").sharedKey)
    }

    @Test func sharedKeyIsNilWithoutUID() {
        func event(uid: String?) -> CalendarEvent {
            CalendarEvent(
                accountID: accountA, id: TestSupport.eventID("1"), calendarID: TestSupport.calendarID("a"), title: "x",
                schedule: .allDay(TestSupport.range(TestSupport.day(2026, 10, 24), days: 1)), iCalendarUID: uid
            )
        }
        #expect(event(uid: nil).sharedKey == nil)
        #expect(event(uid: "  ").sharedKey == nil)
        #expect(event(uid: " uid ").iCalendarUID == "uid")
    }

    @Test func sharedKeyDistinguishesOccurrencesOfRecurringEvent() {
        func event(day: Int) -> CalendarEvent {
            CalendarEvent(
                accountID: accountA, id: TestSupport.eventID("r\(day)"), calendarID: TestSupport.calendarID("a"), title: "x",
                schedule: .allDay(TestSupport.range(TestSupport.day(2026, 10, day), days: 1)), iCalendarUID: "uid-r"
            )
        }
        #expect(event(day: 24).sharedKey != event(day: 25).sharedKey)
    }
}

@Suite struct CalendarVisibilityTests {
    let accountA = TestSupport.accountID("a")
    let accountB = TestSupport.accountID("b")

    func identity(_ account: AccountID, _ calendar: String) -> UserCalendar.Identity {
        UserCalendar.Identity(accountID: account, calendarID: TestSupport.calendarID(calendar))
    }

    @Test func newCalendarsAreVisibleByDefault() {
        let visibility = CalendarVisibility()
        #expect(visibility.isVisible(identity(accountA, "new")))
    }

    @Test func hideAndShowToggleState() {
        var visibility = CalendarVisibility()
        let id = identity(accountA, "a")
        visibility.hide(id)
        #expect(!visibility.isVisible(id))
        #expect(visibility.isVisible(identity(accountA, "b")))
        visibility.hide(id)
        #expect(visibility.hiddenCalendars == [id])
        visibility.show(id)
        #expect(visibility.isVisible(id))
        visibility.show(id)
        #expect(visibility.hiddenCalendars.isEmpty)
    }

    @Test func 複数のカレンダーをまとめて非表示にして表示に戻す() {
        var visibility = CalendarVisibility()
        let ids = [identity(accountA, "a"), identity(accountA, "b"), identity(accountB, "a")]
        visibility.hide(contentsOf: ids)
        #expect(visibility.hiddenCalendars == Set(ids))
        visibility.show(contentsOf: [ids[0], ids[2]])
        #expect(visibility.hiddenCalendars == [ids[1]])
        visibility.show(contentsOf: [UserCalendar.Identity]())
        #expect(visibility.hiddenCalendars == [ids[1]])
    }

    @Test func hidesPerAccountEvenWithSameCalendarID() {
        var visibility = CalendarVisibility()
        visibility.hide(identity(accountA, "holiday"))
        #expect(!visibility.isVisible(identity(accountA, "holiday")))
        #expect(visibility.isVisible(identity(accountB, "holiday")))
    }
}
