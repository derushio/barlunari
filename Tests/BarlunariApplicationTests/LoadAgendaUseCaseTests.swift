import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@Suite struct LoadAgendaUseCaseTests {
    let accountA = Fixtures.accountA
    let accountB = Fixtures.accountB
    let work = Fixtures.userCalendar("work", hex: "#112233")
    let personal = Fixtures.userCalendar("personal", hex: "#AABBCC")
    let day = Fixtures.day(2026, 10, 24)

    func makeUseCase(
        status: CalendarAuthorizationStatus = .fullAccess,
        accounts: [UserAccount]? = nil,
        calendars: [UserCalendar]? = nil,
        events: any CalendarEventRepository,
        visibility: CalendarVisibility = CalendarVisibility(),
        calendarError: (any Error)? = nil
    ) -> LoadAgendaUseCase {
        LoadAgendaUseCase(
            authorizer: FakeCalendarAccessAuthorizer(status: status),
            calendarRepository: InMemoryCalendarRepository(
                accounts: accounts ?? [accountA], calendars: calendars ?? [work, personal], error: calendarError
            ),
            eventRepository: events,
            visibilityRepository: InMemoryCalendarVisibilityRepository(visibility: visibility),
            dateProvider: FixedDateProvider()
        )
    }

    @Test func スナップショットは取得に使ったアカウントを持ち予定のアカウントから引ける() async throws {
        let events = RecordingEventRepository(events: [Fixtures.event("w1", calendar: "work", hour: 14)])
        let snapshot = try await makeUseCase(accounts: [accountA, accountB], events: events)
            .execute(range: Fixtures.oneDay(day))
        #expect(snapshot.accounts == [accountA, accountB])
        #expect(snapshot.account(for: accountA.id)?.name == accountA.name)
        #expect(snapshot.account(for: try AccountID("unknown")) == nil)
    }

    @Test func 表示するすべてのカレンダーの予定を時刻順にまとめる() async throws {
        let events = RecordingEventRepository(events: [
            Fixtures.event("w1", calendar: "work", hour: 14),
            Fixtures.event("p1", calendar: "personal", hour: 9),
        ])
        let snapshot = try await makeUseCase(events: events).execute(range: Fixtures.oneDay(day))
        #expect(snapshot.days.count == 1)
        #expect(snapshot.days[0].events.map(\.eventID.rawValue) == ["p1", "w1"])
    }

    @Test func 表示するカレンダーの予定を範囲の期間で一度に取得する() async throws {
        let events = RecordingEventRepository()
        let range = try DayRange(start: day, dayCount: 7, calendar: Fixtures.calendar)
        _ = try await makeUseCase(events: events).execute(range: range)
        #expect(await events.requestedCalendars == [[work.id, personal.id]])
        #expect(await events.requestedIntervals == [range.dateInterval(calendar: Fixtures.calendar)])
    }

    @Test func 非表示のカレンダーは取得しない() async throws {
        let events = RecordingEventRepository(events: [
            Fixtures.event("w1", calendar: "work", hour: 10),
            Fixtures.event("p1", calendar: "personal", hour: 11),
        ])
        var visibility = CalendarVisibility()
        visibility.hide(personal.id)
        let snapshot = try await makeUseCase(events: events, visibility: visibility).execute(range: Fixtures.oneDay(day))
        #expect(await events.requestedCalendars == [[work.id]])
        #expect(snapshot.days[0].events.map(\.eventID.rawValue) == ["w1"])
        #expect(snapshot.calendars.map(\.id) == [work.id])
    }

    @Test func すべてのカレンダーが非表示なら予定を取得せず空の予定表を返す() async throws {
        let events = RecordingEventRepository(events: [Fixtures.event("w1", calendar: "work", hour: 10)])
        let visibility = CalendarVisibility(hiddenCalendars: [work.id, personal.id])
        let snapshot = try await makeUseCase(events: events, visibility: visibility).execute(range: Fixtures.oneDay(day))
        #expect(await events.requestedCalendars.isEmpty)
        #expect(snapshot.days[0].events.isEmpty)
    }

    @Test func 日ごとの色は予定の並び順で重複なく並ぶ() async throws {
        let events = RecordingEventRepository(events: [
            Fixtures.event("w1", calendar: "work", hour: 10),
            Fixtures.event("p1", calendar: "personal", hour: 12),
            Fixtures.event("w2", calendar: "work", hour: 15),
        ])
        let snapshot = try await makeUseCase(events: events).execute(range: Fixtures.oneDay(day))
        #expect(snapshot.colorsByDay[day] == [work.color, personal.color])
    }

    @Test func 予定のない日は色を持たない() async throws {
        let snapshot = try await makeUseCase(events: RecordingEventRepository()).execute(
            range: try DayRange(start: day, dayCount: 3, calendar: Fixtures.calendar)
        )
        #expect(snapshot.days.count == 3)
        #expect(snapshot.colorsByDay.isEmpty)
    }

    @Test func 辞退した予定は色に数えない() async throws {
        let events = RecordingEventRepository(events: [Fixtures.event("w1", calendar: "work", hour: 10, attendance: .declined)])
        let snapshot = try await makeUseCase(events: events).execute(range: Fixtures.oneDay(day))
        #expect(snapshot.days[0].events.isEmpty)
        #expect(snapshot.colorsByDay.isEmpty)
    }

    @Test func スナップショットは表示したカレンダーをIDから引ける() async throws {
        let snapshot = try await makeUseCase(events: RecordingEventRepository()).execute(range: Fixtures.oneDay(day))
        #expect(snapshot.calendar(for: work.id)?.name == "work")
        #expect(snapshot.calendar(for: Fixtures.userCalendar("none").id) == nil)
    }

    // MARK: - 許可の状態

    @Test func 許可が未決定なら何も取得せずに失敗する() async {
        let events = RecordingEventRepository()
        await #expect(throws: CalendarAccessError.notDetermined) {
            try await makeUseCase(status: .notDetermined, events: events).execute(range: Fixtures.oneDay(day))
        }
        #expect(await events.requestedCalendars.isEmpty)
    }

    @Test func 許可が拒否されていれば何も取得せずに失敗する() async {
        let events = RecordingEventRepository()
        await #expect(throws: CalendarAccessError.denied) {
            try await makeUseCase(status: .denied, events: events).execute(range: Fixtures.oneDay(day))
        }
        #expect(await events.requestedCalendars.isEmpty)
    }

    @Test func カレンダーが一つもなければ失敗する() async {
        let events = RecordingEventRepository()
        await #expect(throws: CalendarAccessError.noCalendars) {
            try await makeUseCase(calendars: [], events: events).execute(range: Fixtures.oneDay(day))
        }
        #expect(await events.requestedCalendars.isEmpty)
    }

    @Test func すべてを非表示にしてもカレンダーがないとは扱わない() async throws {
        let visibility = CalendarVisibility(hiddenCalendars: [work.id, personal.id])
        let snapshot = try await makeUseCase(events: RecordingEventRepository(), visibility: visibility)
            .execute(range: Fixtures.oneDay(day))
        #expect(snapshot.calendars.isEmpty)
    }

    @Test func カレンダーの取得の失敗はそのまま投げる() async {
        await #expect(throws: CocoaError(.fileReadUnknown)) {
            try await makeUseCase(events: RecordingEventRepository(), calendarError: CocoaError(.fileReadUnknown))
                .execute(range: Fixtures.oneDay(day))
        }
    }

    @Test func 予定の取得の失敗はそのまま投げる() async {
        await #expect(throws: CocoaError(.fileReadUnknown)) {
            try await makeUseCase(events: RecordingEventRepository(error: CocoaError(.fileReadUnknown)))
                .execute(range: Fixtures.oneDay(day))
        }
    }

    // MARK: - 複数のアカウント

    @Test func 複数のアカウントの予定をまとめる() async throws {
        let workB = Fixtures.userCalendar("workB", account: accountB)
        let events = RecordingEventRepository(events: [
            Fixtures.event("a1", calendar: "work", hour: 13),
            Fixtures.event("b1", calendar: "workB", account: accountB, hour: 10),
        ])
        let snapshot = try await makeUseCase(
            accounts: [accountA, accountB], calendars: [work, workB], events: events
        ).execute(range: Fixtures.oneDay(day))
        #expect(snapshot.days[0].events.map(\.eventID.rawValue) == ["b1", "a1"])
    }

    @Test func UIDと日時が同じ予定は先のアカウントの一件だけ出す() async throws {
        let holidayA = Fixtures.userCalendar("holiday-a")
        let holidayB = Fixtures.userCalendar("holiday-b", account: accountB)
        let events = RecordingEventRepository(events: [
            Fixtures.event("b1", calendar: "holiday-b", account: accountB, hour: 10, uid: "holiday"),
            Fixtures.event("a1", calendar: "holiday-a", hour: 10, uid: "holiday"),
        ])
        let snapshot = try await makeUseCase(
            accounts: [accountA, accountB], calendars: [holidayA, holidayB], events: events
        ).execute(range: Fixtures.oneDay(day))
        #expect(snapshot.days[0].events.map(\.accountID) == [accountA.id])
    }

    @Test func アカウントの並び順はリポジトリが返した順に従う() async throws {
        let holidayA = Fixtures.userCalendar("holiday-a")
        let holidayB = Fixtures.userCalendar("holiday-b", account: accountB)
        let events = RecordingEventRepository(events: [
            Fixtures.event("a1", calendar: "holiday-a", hour: 10, uid: "holiday"),
            Fixtures.event("b1", calendar: "holiday-b", account: accountB, hour: 10, uid: "holiday"),
        ])
        let snapshot = try await makeUseCase(
            accounts: [accountB, accountA], calendars: [holidayA, holidayB], events: events
        ).execute(range: Fixtures.oneDay(day))
        #expect(snapshot.days[0].events.map(\.accountID) == [accountB.id])
    }

    @Test func 先のアカウントのカレンダーを非表示にすると後のアカウントの重複した予定が残る() async throws {
        let holidayA = Fixtures.userCalendar("holiday-a")
        let holidayB = Fixtures.userCalendar("holiday-b", account: accountB)
        let events = RecordingEventRepository(events: [
            Fixtures.event("a1", calendar: "holiday-a", hour: 10, uid: "holiday"),
            Fixtures.event("b1", calendar: "holiday-b", account: accountB, hour: 10, uid: "holiday"),
        ])
        let visibility = CalendarVisibility(hiddenCalendars: [holidayA.id])
        let snapshot = try await makeUseCase(
            accounts: [accountA, accountB], calendars: [holidayA, holidayB], events: events, visibility: visibility
        ).execute(range: Fixtures.oneDay(day))
        #expect(snapshot.days[0].events.map(\.accountID) == [accountB.id])
    }
}
