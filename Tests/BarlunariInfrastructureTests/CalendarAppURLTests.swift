import Foundation
import BarlunariDomain
import Testing

@testable import BarlunariInfrastructure

@Suite struct CalendarAppURLTests {
    var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    /// 2026-10-24 14:00 JST = 05:00 UTC
    var start: Date { tokyo.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 14))! }
    /// 2026-10-24 00:00 JST = 2026-10-23 15:00 UTC
    var midnight: Date { tokyo.date(from: DateComponents(year: 2026, month: 10, day: 24))! }

    @Test func 繰り返しのない予定は識別子だけを入れる() {
        let url = CalendarAppURL.url(
            calendarItemIdentifier: "ABC-123", startDate: start, isAllDay: false, hasRecurrenceRules: false, calendar: tokyo
        )
        #expect(url?.absoluteString == "ical://ekevent/ABC-123?method=show&options=more")
    }

    @Test func 繰り返しの予定は回の開始日時をUTCで入れる() {
        let url = CalendarAppURL.url(
            calendarItemIdentifier: "ABC-123", startDate: start, isAllDay: false, hasRecurrenceRules: true, calendar: tokyo
        )
        #expect(url?.absoluteString == "ical://ekevent/20261024T050000Z/ABC-123?method=show&options=more")
    }

    @Test func 繰り返しの終日の予定は暦のタイムゾーンの日付を入れる() {
        let url = CalendarAppURL.url(
            calendarItemIdentifier: "ABC-123", startDate: midnight, isAllDay: true, hasRecurrenceRules: true, calendar: tokyo
        )
        #expect(url?.absoluteString == "ical://ekevent/20261024T000000Z/ABC-123?method=show&options=more")
    }

    @Test func 終日でなければ同じ時刻でもUTCで書式化する() {
        let text = CalendarAppURL.startText(of: midnight, isAllDay: false, calendar: tokyo)
        #expect(text == "20261023T150000Z")
    }

    @Test func 識別子はパーセントエンコードする() {
        let url = CalendarAppURL.url(
            calendarItemIdentifier: "a b/c?d", startDate: start, isAllDay: false, hasRecurrenceRules: false, calendar: tokyo
        )
        #expect(url?.absoluteString == "ical://ekevent/a%20b/c%3Fd?method=show&options=more")
    }

    @Test func 識別子が空ならURLを作らない() {
        #expect(CalendarAppURL.url(
            calendarItemIdentifier: "", startDate: start, isAllDay: false, hasRecurrenceRules: false, calendar: tokyo
        ) == nil)
    }
}

@Suite struct EventKitEventLocatorTests {
    func identity(_ eventID: String) throws -> CalendarEvent.Identity {
        CalendarEvent(
            accountID: try AccountID("source-a"), id: try EventID(eventID), calendarID: try CalendarID("cal-1"),
            title: "", schedule: .timed(DateInterval(start: Date(timeIntervalSince1970: 0), duration: 60))
        ).id
    }

    @Test func 予定の識別子と回の開始日時に分ける() throws {
        let locator = try #require(EventKitEventLocator(try identity("ABC:123@1792990800")))
        #expect(locator.identifier == "ABC:123")
        #expect(locator.startSeconds == 1_792_990_800)
        #expect(locator.sourceIdentifier == "source-a")
        #expect(locator.calendarIdentifier == "cal-1")
    }

    @Test func 識別子に区切りの文字が含まれても最後の区切りで分ける() throws {
        let locator = try #require(EventKitEventLocator(try identity("a@b@100")))
        #expect(locator.identifier == "a@b")
        #expect(locator.startSeconds == 100)
    }

    @Test(arguments: ["no-separator", "@100", "id@abc", "id@"])
    func 開始日時を読めない予定は探せない(eventID: String) throws {
        #expect(EventKitEventLocator(try identity(eventID)) == nil)
    }

    @Test func 取得範囲は回の開始日時を含む() throws {
        let locator = try #require(EventKitEventLocator(try identity("id@100")))
        #expect(locator.searchInterval.contains(Date(timeIntervalSince1970: 100)))
    }

    @Test func 識別子と開始日時が一致する回だけを選ぶ() throws {
        let locator = try #require(EventKitEventLocator(try identity("id@100")))
        let at100 = Date(timeIntervalSince1970: 100)
        let at200 = Date(timeIntervalSince1970: 200)
        #expect(locator.matches(identifier: "id", calendarItemIdentifier: "item", startDate: at100))
        #expect(!locator.matches(identifier: "id", calendarItemIdentifier: "item", startDate: at200))
        #expect(!locator.matches(identifier: "other", calendarItemIdentifier: "item", startDate: at100))
    }

    @Test func eventIdentifierがない予定はcalendarItemIdentifierで選ぶ() throws {
        let locator = try #require(EventKitEventLocator(try identity("item@100")))
        let at100 = Date(timeIntervalSince1970: 100)
        #expect(locator.matches(identifier: nil, calendarItemIdentifier: "item", startDate: at100))
        #expect(locator.matches(identifier: "", calendarItemIdentifier: "item", startDate: at100))
    }
}
