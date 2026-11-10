import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@Suite struct LoadUpcomingEventsUseCaseTests {
    let accountA = Fixtures.accountA
    let accountB = Fixtures.accountB
    let work = Fixtures.userCalendar("work", hex: "#112233")
    let personal = Fixtures.userCalendar("personal", hex: "#AABBCC")
    let now = SampleData.now

    func makeUseCase(
        status: CalendarAuthorizationStatus = .fullAccess,
        accounts: [UserAccount]? = nil,
        calendars: [UserCalendar]? = nil,
        events: any CalendarEventRepository,
        visibility: CalendarVisibility = CalendarVisibility(),
        settings: CountdownTargetSettings = CountdownTargetSettings()
    ) -> LoadUpcomingEventsUseCase {
        LoadUpcomingEventsUseCase(
            authorizer: FakeCalendarAccessAuthorizer(status: status),
            calendarRepository: InMemoryCalendarRepository(
                accounts: accounts ?? [accountA], calendars: calendars ?? [work, personal]
            ),
            eventRepository: events,
            visibilityRepository: InMemoryCalendarVisibilityRepository(visibility: visibility),
            settingsRepository: InMemoryCountdownTargetSettingsRepository(settings: settings),
            dateProvider: FixedDateProvider()
        )
    }

    @Test(arguments: [CalendarAuthorizationStatus.notDetermined, .denied])
    func 完全アクセスでなければ許可の状態に応じたエラーを投げる(status: CalendarAuthorizationStatus) async {
        let useCase = makeUseCase(status: status, events: RecordingEventRepository())
        await #expect(throws: CalendarAccessError.self) { try await useCase.execute() }
    }

    @Test func カレンダーがなければエラーを投げる() async {
        let useCase = makeUseCase(calendars: [], events: RecordingEventRepository())
        await #expect(throws: CalendarAccessError.noCalendars) { try await useCase.execute() }
    }

    @Test func 現在から48時間の範囲を表示中のカレンダーで取得する() async throws {
        let events = RecordingEventRepository()
        var visibility = CalendarVisibility()
        visibility.hide(personal.id)
        let upcoming = try await makeUseCase(events: events, visibility: visibility).execute()
        #expect(await events.requestedIntervals == [DateInterval(start: now, duration: 48 * 3600)])
        #expect(await events.requestedCalendars == [[work.id]])
        #expect(upcoming.rangeEnd == now.addingTimeInterval(48 * 3600))
    }

    @Test func すべて非表示なら取得せず空を返す() async throws {
        let events = RecordingEventRepository()
        var visibility = CalendarVisibility()
        visibility.hide(contentsOf: [work.id, personal.id])
        let upcoming = try await makeUseCase(events: events, visibility: visibility).execute()
        #expect(upcoming.events.isEmpty)
        #expect(await events.requestedIntervals.isEmpty)
    }

    @Test func 辞退した予定も取得し重複を一つにする() async throws {
        let events = RecordingEventRepository(events: [
            Fixtures.event("declined", calendar: "work", hour: 13, attendance: .declined),
            Fixtures.event("a", calendar: "work", hour: 14, uid: "same"),
            Fixtures.event("b", calendar: "work", account: accountB, hour: 14, uid: "same"),
        ])
        let work2 = Fixtures.userCalendar("work", account: accountB)
        let upcoming = try await makeUseCase(
            accounts: [accountA, accountB], calendars: [work, work2], events: events
        ).execute()
        #expect(upcoming.events.map(\.eventID.rawValue).sorted() == ["a", "declined"])
    }

    @Test func 設定を一緒に返し残り時間の計算に使える() async throws {
        let first = Fixtures.event("first", calendar: "work", hour: 13)
        let second = Fixtures.event("second", calendar: "work", hour: 15)
        var settings = CountdownTargetSettings()
        settings.set(first.id, isTarget: false)
        let upcoming = try await makeUseCase(events: RecordingEventRepository(events: [first, second]), settings: settings)
            .execute()
        #expect(upcoming.settings == settings)
        #expect(upcoming.countdown(at: now)?.remainingMinutes == 180)
    }

    @Test func 辞退した予定は設定が対象でも残り時間に数えない() async throws {
        let declined = Fixtures.event("declined", calendar: "work", hour: 13, attendance: .declined)
        let later = Fixtures.event("later", calendar: "work", hour: 15)
        var settings = CountdownTargetSettings()
        settings.set(declined.id, isTarget: true)
        let upcoming = try await makeUseCase(events: RecordingEventRepository(events: [declined, later]), settings: settings)
            .execute()
        #expect(upcoming.countdown(at: now)?.remainingMinutes == 180)
    }
}

@Suite struct SetCountdownTargetUseCaseTests {
    let account = SampleData.googleAccount.id

    func identity(_ id: String) -> CalendarEvent.Identity {
        CalendarEvent.Identity(
            accountID: account, calendarID: try! CalendarID("work"), eventID: try! EventID(id)
        )
    }

    func event(_ id: String, allDay: Bool = false) -> CalendarEvent {
        let day = try! CalendarDay(year: 2026, month: 10, day: 25)
        return CalendarEvent(
            accountID: account, id: try! EventID(id), calendarID: try! CalendarID("work"), title: id,
            schedule: allDay
                ? .allDay(try! DayRange(start: day, end: try! CalendarDay(year: 2026, month: 10, day: 26)))
                : .timed(DateInterval(start: SampleData.now.addingTimeInterval(3600), duration: 3600))
        )
    }

    @Test func 対象にも対象外にも切り替えて保存できる() async throws {
        let repository = InMemoryCountdownTargetSettingsRepository()
        let useCase = SetCountdownTargetUseCase(repository: repository)
        try await useCase.execute(event: identity("a"), isTarget: false)
        #expect(await !repository.load().isTarget(event("a")))
        try await useCase.execute(event: identity("a"), isTarget: true)
        #expect(await repository.load().isTarget(event("a")))
        try await useCase.execute(event: identity("b"), isTarget: true)
        #expect(await repository.load().isTarget(event("b", allDay: true)))
    }

    @Test func 開始を過ぎた予定の設定も消えない() async throws {
        let repository = InMemoryCountdownTargetSettingsRepository()
        let useCase = SetCountdownTargetUseCase(repository: repository)
        let past = CalendarEvent(
            accountID: account, id: try EventID("past"), calendarID: try CalendarID("work"), title: "past",
            schedule: .timed(DateInterval(start: SampleData.now.addingTimeInterval(-7200), duration: 3600))
        )
        try await useCase.execute(event: past.id, isTarget: false)
        try await useCase.execute(event: identity("other"), isTarget: false)
        #expect(await !repository.load().isTarget(past))
    }

    @Test func 保存に失敗したら投げて変更を保存しない() async {
        struct SaveFailure: Error {}
        let repository = InMemoryCountdownTargetSettingsRepository(error: SaveFailure())
        let useCase = SetCountdownTargetUseCase(repository: repository)
        await #expect(throws: SaveFailure.self) {
            try await useCase.execute(event: identity("a"), isTarget: false)
        }
        #expect(await repository.load() == CountdownTargetSettings())
    }

    @Test func 読み込みは保存した設定を返す() async {
        var initial = CountdownTargetSettings()
        initial.set(identity("a"), isTarget: false)
        let useCase = LoadCountdownTargetSettingsUseCase(repository: InMemoryCountdownTargetSettingsRepository(settings: initial))
        #expect(await useCase.execute() == initial)
    }
}
