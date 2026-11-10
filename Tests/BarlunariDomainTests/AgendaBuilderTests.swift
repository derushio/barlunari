import Foundation
import Testing
@testable import BarlunariDomain

@Suite struct AgendaBuilderTests {
    let calendar = TestSupport.calendar()
    let accountA = TestSupport.accountID("a")
    let accountB = TestSupport.accountID("b")
    let work = TestSupport.calendarID("work")
    let personal = TestSupport.calendarID("personal")
    let builder = AgendaBuilder()

    func allDay(
        _ id: String, _ title: String, from start: CalendarDay, days: Int,
        calendarID: CalendarID? = nil, account: AccountID? = nil, attendance: AttendanceStatus = .notApplicable,
        uid: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            accountID: account ?? accountA, id: TestSupport.eventID(id), calendarID: calendarID ?? work, title: title,
            schedule: .allDay(TestSupport.range(start, days: days)), attendance: attendance, iCalendarUID: uid
        )
    }

    func timed(
        _ id: String, _ title: String, from start: Date, to end: Date,
        calendarID: CalendarID? = nil, account: AccountID? = nil, attendance: AttendanceStatus = .accepted,
        uid: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            accountID: account ?? accountA, id: TestSupport.eventID(id), calendarID: calendarID ?? work, title: title,
            schedule: .timed(DateInterval(start: start, end: end)), attendance: attendance, iCalendarUID: uid
        )
    }

    func identities(_ ids: Set<CalendarID>, accounts: [AccountID]? = nil) -> Set<UserCalendar.Identity> {
        Set((accounts ?? [accountA]).flatMap { account in
            ids.map { UserCalendar.Identity(accountID: account, calendarID: $0) }
        })
    }

    func build(
        _ events: [CalendarEvent], visible: Set<CalendarID>? = nil, accounts: [AccountID]? = nil,
        includesDeclined: Bool = true, from start: CalendarDay, days: Int
    ) -> [DayAgenda] {
        builder.build(
            events: events, visibleCalendars: identities(visible ?? [work, personal], accounts: accounts),
            accountOrder: accounts ?? [accountA], includesDeclined: includesDeclined,
            range: TestSupport.range(start, days: days), calendar: calendar
        )
    }

    func titles(_ agenda: DayAgenda) -> [String] { agenda.events.map(\.title) }

    @Test func returnsEveryDayEvenWithoutEvents() {
        let result = build([], from: TestSupport.day(2026, 10, 24), days: 3)
        #expect(result.map(\.day) == [TestSupport.day(2026, 10, 24), TestSupport.day(2026, 10, 25), TestSupport.day(2026, 10, 26)])
        #expect(result.allSatisfy { $0.events.isEmpty })
    }

    @Test func multiDayAllDayEventAppearsOnEveryDayWithExclusiveEnd() {
        let event = allDay("1", "合宿", from: TestSupport.day(2026, 10, 25), days: 3)
        let result = build([event], from: TestSupport.day(2026, 10, 24), days: 6)
        #expect(result.map { titles($0) } == [[], ["合宿"], ["合宿"], ["合宿"], [], []])
    }

    @Test func timedEventCrossingMidnightAppearsOnBothDays() {
        let event = timed("1", "夜行バス", from: TestSupport.date(2026, 10, 24, 23, 0), to: TestSupport.date(2026, 10, 25, 6, 0))
        let result = build([event], from: TestSupport.day(2026, 10, 24), days: 3)
        #expect(result.map { titles($0) } == [["夜行バス"], ["夜行バス"], []])
    }

    @Test func timedEventEndingExactlyAtMidnightExcludesEndDay() {
        let event = timed("1", "深夜作業", from: TestSupport.date(2026, 10, 24, 22, 0), to: TestSupport.date(2026, 10, 25, 0, 0))
        let result = build([event], from: TestSupport.day(2026, 10, 24), days: 2)
        #expect(result.map { titles($0) } == [["深夜作業"], []])
    }

    @Test func timedEventSpanningSeveralDaysFillsMiddleDays() {
        let event = timed("1", "出張", from: TestSupport.date(2026, 10, 24, 10, 0), to: TestSupport.date(2026, 10, 27, 9, 0))
        let result = build([event], from: TestSupport.day(2026, 10, 23), days: 6)
        #expect(result.map { titles($0) } == [[], ["出張"], ["出張"], ["出張"], ["出張"], []])
    }

    @Test func zeroLengthEventAppearsOnItsStartDayOnly() {
        let moment = TestSupport.date(2026, 10, 25, 0, 0)
        let event = timed("1", "締切", from: moment, to: moment)
        let result = build([event], from: TestSupport.day(2026, 10, 24), days: 3)
        #expect(result.map { titles($0) } == [[], ["締切"], []])
    }

    @Test func dayBoundaryFollowsCalendarTimeZone() {
        // UTC の 10/24 16:00-17:00 は東京では 10/25 の早朝
        let utc = TestSupport.calendar("UTC")
        let event = timed("1", "早朝", from: TestSupport.date(2026, 10, 24, 16, 0, calendar: utc), to: TestSupport.date(2026, 10, 24, 17, 0, calendar: utc))
        let tokyo = build([event], from: TestSupport.day(2026, 10, 24), days: 2)
        #expect(tokyo.map { titles($0) } == [[], ["早朝"]])
        let inUTC = builder.build(
            events: [event], visibleCalendars: identities([work]), accountOrder: [accountA], includesDeclined: true,
            range: TestSupport.range(TestSupport.day(2026, 10, 24), days: 2, calendar: utc), calendar: utc
        )
        #expect(inUTC.map { titles($0) } == [["早朝"], []])
    }

    @Test func keepsDeclinedEvents() {
        let events = [
            timed("1", "参加", from: TestSupport.date(2026, 10, 24, 10, 0), to: TestSupport.date(2026, 10, 24, 11, 0)),
            timed("2", "辞退", from: TestSupport.date(2026, 10, 24, 12, 0), to: TestSupport.date(2026, 10, 24, 13, 0), attendance: .declined),
            allDay("3", "終日辞退", from: TestSupport.day(2026, 10, 24), days: 1, attendance: .declined),
            timed("4", "未回答", from: TestSupport.date(2026, 10, 24, 14, 0), to: TestSupport.date(2026, 10, 24, 15, 0), attendance: .needsAction),
        ]
        let result = build(events, from: TestSupport.day(2026, 10, 24), days: 1)
        #expect(titles(result[0]) == ["終日辞退", "参加", "辞退", "未回答"])
    }

    @Test func 辞退した予定を含めない設定なら辞退した予定だけを除く() {
        let events = [
            timed("1", "参加", from: TestSupport.date(2026, 10, 24, 10, 0), to: TestSupport.date(2026, 10, 24, 11, 0)),
            timed("2", "辞退", from: TestSupport.date(2026, 10, 24, 12, 0), to: TestSupport.date(2026, 10, 24, 13, 0), attendance: .declined),
            allDay("3", "終日辞退", from: TestSupport.day(2026, 10, 24), days: 2, attendance: .declined),
            timed("4", "未回答", from: TestSupport.date(2026, 10, 24, 14, 0), to: TestSupport.date(2026, 10, 24, 15, 0), attendance: .needsAction),
            allDay("5", "終日", from: TestSupport.day(2026, 10, 24), days: 1),
        ]
        let result = build(events, includesDeclined: false, from: TestSupport.day(2026, 10, 24), days: 2)
        #expect(titles(result[0]) == ["終日", "参加", "未回答"])
        #expect(result[1].events.isEmpty)
    }

    @Test func 辞退した予定を含める設定なら辞退した予定を残す() {
        let events = [
            timed("2", "辞退", from: TestSupport.date(2026, 10, 24, 12, 0), to: TestSupport.date(2026, 10, 24, 13, 0), attendance: .declined),
        ]
        let result = build(events, includesDeclined: true, from: TestSupport.day(2026, 10, 24), days: 1)
        #expect(titles(result[0]) == ["辞退"])
    }

    @Test func 辞退した予定の絞り込みは重複の除去の後に行う() {
        // 先のアカウントの予定が辞退で、後のアカウントの同じ予定が承諾。重複の除去で残るのは先のアカウントの予定なので、
        // 絞り込みを先にすると後のアカウントの予定が残ってしまう。除去の後に絞り込むと、予定は現れない。
        let events = [
            timed("a-1", "会議", from: tenToEleven.0, to: tenToEleven.1, account: accountA, attendance: .declined, uid: "u"),
            timed("b-1", "会議", from: tenToEleven.0, to: tenToEleven.1, account: accountB, attendance: .accepted, uid: "u"),
        ]
        let order = [accountA, accountB]
        #expect(build(events, accounts: order, includesDeclined: false, from: oct24, days: 1)[0].events.isEmpty)
        #expect(build(events, accounts: order, includesDeclined: true, from: oct24, days: 1)[0].events.map(\.accountID) == [accountA])
    }

    @Test func excludesHiddenCalendars() {
        let events = [
            timed("1", "仕事", from: TestSupport.date(2026, 10, 24, 10, 0), to: TestSupport.date(2026, 10, 24, 11, 0), calendarID: work),
            timed("2", "私用", from: TestSupport.date(2026, 10, 24, 12, 0), to: TestSupport.date(2026, 10, 24, 13, 0), calendarID: personal),
        ]
        let result = build(events, visible: [personal], from: TestSupport.day(2026, 10, 24), days: 1)
        #expect(titles(result[0]) == ["私用"])
        #expect(build(events, visible: [], from: TestSupport.day(2026, 10, 24), days: 1)[0].events.isEmpty)
    }

    @Test func ordersAllDayFirstThenByStartThenTitle() {
        let nine = TestSupport.date(2026, 10, 24, 9, 0)
        let ten = TestSupport.date(2026, 10, 24, 10, 0)
        let events = [
            timed("1", "B 会議", from: ten, to: ten.addingTimeInterval(3600)),
            timed("2", "A 会議", from: ten, to: ten.addingTimeInterval(1800)),
            timed("3", "朝会", from: nine, to: nine.addingTimeInterval(900)),
            allDay("4", "祝日", from: TestSupport.day(2026, 10, 24), days: 1),
            allDay("5", "締切", from: TestSupport.day(2026, 10, 24), days: 1),
        ]
        let result = build(events, from: TestSupport.day(2026, 10, 24), days: 1)
        #expect(titles(result[0]) == ["祝日", "締切", "朝会", "A 会議", "B 会議"])
    }

    @Test func orderingIsStableForIdenticalTitlesAndTimes() {
        let ten = TestSupport.date(2026, 10, 24, 10, 0)
        let events = [
            timed("2", "同じ", from: ten, to: ten.addingTimeInterval(60)),
            timed("1", "同じ", from: ten, to: ten.addingTimeInterval(60)),
        ]
        let result = build(events, from: TestSupport.day(2026, 10, 24), days: 1)
        #expect(result[0].events.map(\.eventID.rawValue) == ["1", "2"])
        #expect(build(events.reversed(), from: TestSupport.day(2026, 10, 24), days: 1) == result)
    }

    @Test func eventsOutsideRangeAreIgnored() {
        let events = [
            timed("1", "前日", from: TestSupport.date(2026, 10, 23, 10, 0), to: TestSupport.date(2026, 10, 23, 11, 0)),
            timed("2", "翌日", from: TestSupport.date(2026, 10, 25, 0, 0), to: TestSupport.date(2026, 10, 25, 1, 0)),
        ]
        let result = build(events, from: TestSupport.day(2026, 10, 24), days: 1)
        #expect(result[0].events.isEmpty)
    }

    @Test func handlesDaylightSavingDay() {
        let newYork = TestSupport.calendar("America/New_York")
        // 2026-11-01 は 25 時間の日。23:30 開始で翌日 0:00 までの予定は 11/1 のみ
        let event = CalendarEvent(
            accountID: accountA, id: TestSupport.eventID("1"), calendarID: work, title: "夜",
            schedule: .timed(DateInterval(
                start: TestSupport.date(2026, 11, 1, 23, 30, calendar: newYork),
                end: TestSupport.date(2026, 11, 2, 0, 0, calendar: newYork)
            ))
        )
        let range = TestSupport.range(TestSupport.day(2026, 11, 1), days: 2, calendar: newYork)
        let result = builder.build(
            events: [event], visibleCalendars: identities([work]), accountOrder: [accountA], includesDeclined: true, range: range, calendar: newYork
        )
        #expect(result.map { titles($0) } == [["夜"], []])
    }

    // MARK: - colorsByDay

    @Test func 日ごとの色は予定の並び順で重複なく並ぶ() {
        let workCalendar = UserCalendar(accountID: accountA, id: work, name: "仕事", color: try! CalendarColor(hex: "#112233"))
        let personalCalendar = UserCalendar(accountID: accountA, id: personal, name: "私用", color: try! CalendarColor(hex: "#AABBCC"))
        let day = TestSupport.day(2026, 10, 24)
        let days = build([
            timed("w1", "a", from: TestSupport.date(2026, 10, 24, 10), to: TestSupport.date(2026, 10, 24, 11)),
            timed("p1", "b", from: TestSupport.date(2026, 10, 24, 12), to: TestSupport.date(2026, 10, 24, 13), calendarID: personal),
            timed("w2", "c", from: TestSupport.date(2026, 10, 24, 14), to: TestSupport.date(2026, 10, 24, 15)),
        ], from: day, days: 2)
        let colors = builder.colorsByDay(of: days, calendars: [workCalendar, personalCalendar])
        #expect(colors[day] == [workCalendar.color, personalCalendar.color])
        #expect(colors[TestSupport.day(2026, 10, 25)] == nil)
    }

    @Test func 色を引けないカレンダーの予定は色に数えない() {
        let day = TestSupport.day(2026, 10, 24)
        let days = build(
            [timed("p1", "b", from: TestSupport.date(2026, 10, 24, 12), to: TestSupport.date(2026, 10, 24, 13), calendarID: personal)],
            from: day, days: 1
        )
        let workCalendar = UserCalendar(accountID: accountA, id: work, name: "仕事", color: try! CalendarColor(hex: "#112233"))
        #expect(builder.colorsByDay(of: days, calendars: [workCalendar]).isEmpty)
    }

    @Test func 辞退した予定は色に数えず辞退だけの日はキーを持たない() {
        let workCalendar = UserCalendar(accountID: accountA, id: work, name: "仕事", color: try! CalendarColor(hex: "#112233"))
        let personalCalendar = UserCalendar(accountID: accountA, id: personal, name: "私用", color: try! CalendarColor(hex: "#AABBCC"))
        let day = TestSupport.day(2026, 10, 24)
        let days = build([
            timed("w1", "a", from: TestSupport.date(2026, 10, 24, 10), to: TestSupport.date(2026, 10, 24, 11)),
            timed("p1", "b", from: TestSupport.date(2026, 10, 24, 12), to: TestSupport.date(2026, 10, 24, 13), calendarID: personal, attendance: .declined),
            timed("p2", "c", from: TestSupport.date(2026, 10, 25, 12), to: TestSupport.date(2026, 10, 25, 13), calendarID: personal, attendance: .declined),
        ], from: day, days: 2)
        #expect(days.map { titles($0) } == [["a", "b"], ["c"]])
        let colors = builder.colorsByDay(of: days, calendars: [workCalendar, personalCalendar])
        #expect(colors[day] == [workCalendar.color])
        #expect(colors[TestSupport.day(2026, 10, 25)] == nil)
    }

    // MARK: - 複数のアカウント

    private var oct24: CalendarDay { TestSupport.day(2026, 10, 24) }
    private var tenToEleven: (Date, Date) { (TestSupport.date(2026, 10, 24, 10), TestSupport.date(2026, 10, 24, 11)) }

    @Test func UIDと日時が同じ予定は先のアカウントの予定を一件だけ残す() {
        let holiday = TestSupport.calendarID("holiday")
        let events = [
            allDay("b-1", "文化の日", from: oct24, days: 1, calendarID: holiday, account: accountB, uid: "holiday-1"),
            allDay("a-1", "文化の日", from: oct24, days: 1, calendarID: holiday, account: accountA, uid: "holiday-1"),
        ]
        let result = build(events, visible: [holiday], accounts: [accountA, accountB], from: oct24, days: 1)
        #expect(result[0].events.map(\.accountID) == [accountA])
    }

    @Test func 重複の除去はアカウントの並び順に従う() {
        let events = [
            allDay("a-1", "祝日", from: oct24, days: 1, account: accountA, uid: "u"),
            allDay("b-1", "祝日", from: oct24, days: 1, account: accountB, uid: "u"),
        ]
        let result = build(events, accounts: [accountB, accountA], from: oct24, days: 1)
        #expect(result[0].events.map(\.accountID) == [accountB])
    }

    @Test func 並び順にないアカウントは最後に回る() {
        let accountC = TestSupport.accountID("c")
        let events = [
            allDay("c-1", "祝日", from: oct24, days: 1, account: accountC, uid: "u"),
            allDay("b-1", "祝日", from: oct24, days: 1, account: accountB, uid: "u"),
        ]
        let result = builder.build(
            events: events, visibleCalendars: identities([work], accounts: [accountB, accountC]),
            accountOrder: [accountA], includesDeclined: true,
            range: TestSupport.range(oct24, days: 1), calendar: calendar
        )
        #expect(result[0].events.map(\.accountID) == [accountB])
    }

    @Test func UIDが違えば別の予定として残す() {
        let events = [
            allDay("a-1", "共有", from: oct24, days: 1, account: accountA, uid: "u1"),
            allDay("b-1", "共有", from: oct24, days: 1, account: accountB, uid: "u1"),
            allDay("b-2", "別の予定", from: oct24, days: 1, account: accountB, uid: "u2"),
        ]
        let result = build(events, accounts: [accountA, accountB], from: oct24, days: 1)
        #expect(titles(result[0]).sorted() == ["共有", "別の予定"].sorted())
    }

    @Test func UIDが同じでも日時が違えば別の回として残す() {
        let events = [
            allDay("r-1", "定例", from: oct24, days: 1, account: accountA, uid: "weekly"),
            allDay("r-2", "定例", from: TestSupport.day(2026, 10, 25), days: 1, account: accountA, uid: "weekly"),
        ]
        let result = build(events, from: oct24, days: 2)
        #expect(result.map { titles($0) } == [["定例"], ["定例"]])
    }

    @Test func UIDを持たない予定は重複の除去の対象にしない() {
        let events = [
            allDay("a-1", "メモ", from: oct24, days: 1, account: accountA),
            allDay("b-1", "メモ", from: oct24, days: 1, account: accountB),
        ]
        let result = build(events, accounts: [accountA, accountB], from: oct24, days: 1)
        #expect(result[0].events.count == 2)
    }

    @Test func 同じアカウントの重複は入力で先の予定を残す() {
        let events = [
            allDay("second-calendar", "祝日", from: oct24, days: 1, calendarID: personal, account: accountA, uid: "u"),
            allDay("first-calendar", "祝日", from: oct24, days: 1, calendarID: work, account: accountA, uid: "u"),
        ]
        let result = build(events, from: oct24, days: 1)
        #expect(result[0].events.map(\.eventID.rawValue) == ["second-calendar"])
        let reversed = build(events.reversed(), from: oct24, days: 1)
        #expect(reversed[0].events.map(\.eventID.rawValue) == ["first-calendar"])
    }

    @Test func 先のアカウントのカレンダーが非表示なら後のアカウントの予定を残す() {
        let events = [
            allDay("a-1", "祝日", from: oct24, days: 1, account: accountA, uid: "u"),
            allDay("b-1", "祝日", from: oct24, days: 1, account: accountB, uid: "u"),
        ]
        let result = builder.build(
            events: events, visibleCalendars: [UserCalendar.Identity(accountID: accountB, calendarID: work)],
            accountOrder: [accountA, accountB], includesDeclined: true,
            range: TestSupport.range(oct24, days: 1), calendar: calendar
        )
        #expect(result[0].events.map(\.accountID) == [accountB])
    }

    @Test func アカウントをまたぐ重複の除去は入力の順序に左右されない() {
        let events = [
            allDay("a-1", "祝日", from: oct24, days: 1, account: accountA, uid: "u1"),
            allDay("b-1", "祝日", from: oct24, days: 1, account: accountB, uid: "u1"),
            timed("b-2", "会議", from: tenToEleven.0, to: tenToEleven.1, account: accountB, uid: "u2"),
            timed("a-2", "会議", from: tenToEleven.0, to: tenToEleven.1, account: accountA, uid: "u2"),
        ]
        let order = [accountA, accountB]
        #expect(build(events, accounts: order, from: oct24, days: 1) == build(events.reversed(), accounts: order, from: oct24, days: 1))
        #expect(build(events, accounts: order, from: oct24, days: 1)[0].events.map(\.accountID) == [accountA, accountA])
    }

    @Test func 日ごとの色はアカウントごとのカレンダーから引く() {
        let blue = try! CalendarColor(hex: "#0000FF")
        let red = try! CalendarColor(hex: "#FF0000")
        let calendars = [
            UserCalendar(accountID: accountA, id: work, name: "A", color: blue),
            UserCalendar(accountID: accountB, id: work, name: "B", color: red),
        ]
        let days = build(
            [timed("1", "b", from: tenToEleven.0, to: tenToEleven.1, account: accountB)],
            accounts: [accountA, accountB], from: oct24, days: 1
        )
        #expect(builder.colorsByDay(of: days, calendars: calendars)[oct24] == [red])
    }
}

@Suite struct AgendaBuilderCandidateEventsTests {
    let builder = AgendaBuilder()
    let accountA = TestSupport.accountID("a")
    let accountB = TestSupport.accountID("b")
    let work = TestSupport.calendarID("work")
    let hidden = TestSupport.calendarID("hidden")
    let start = TestSupport.date(2026, 10, 24, 14, 0)

    func event(
        _ id: String, account: AccountID, calendarID: CalendarID? = nil,
        attendance: AttendanceStatus = .accepted, uid: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            accountID: account, id: TestSupport.eventID(id), calendarID: calendarID ?? work, title: id,
            schedule: .timed(DateInterval(start: start, duration: 3600)), attendance: attendance, iCalendarUID: uid
        )
    }

    func visible(_ accounts: [AccountID]) -> Set<UserCalendar.Identity> {
        Set(accounts.map { UserCalendar.Identity(accountID: $0, calendarID: work) })
    }

    @Test func 非表示のカレンダーの予定を除く() {
        let result = builder.candidateEvents(
            from: [event("a", account: accountA), event("b", account: accountA, calendarID: hidden)],
            visibleCalendars: visible([accountA]), accountOrder: [accountA], includesDeclined: true
        )
        #expect(result.map(\.title) == ["a"])
    }

    @Test func 重複を除きアカウントの並びで先の予定を残す() {
        let result = builder.candidateEvents(
            from: [event("b", account: accountB, uid: "u"), event("a", account: accountA, uid: "u")],
            visibleCalendars: visible([accountA, accountB]), accountOrder: [accountA, accountB], includesDeclined: true
        )
        #expect(result.map(\.title) == ["a"])
    }

    @Test func 辞退は重複の除去のあとに除く() {
        let events = [event("a", account: accountA, attendance: .declined, uid: "u"), event("b", account: accountB, uid: "u")]
        let kept = builder.candidateEvents(
            from: events, visibleCalendars: visible([accountA, accountB]),
            accountOrder: [accountA, accountB], includesDeclined: false
        )
        #expect(kept.isEmpty)
        let included = builder.candidateEvents(
            from: events, visibleCalendars: visible([accountA, accountB]),
            accountOrder: [accountA, accountB], includesDeclined: true
        )
        #expect(included.map(\.title) == ["a"])
    }
}
