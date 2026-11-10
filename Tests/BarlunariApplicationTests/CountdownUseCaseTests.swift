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
        exclusions: CountdownExclusions = CountdownExclusions()
    ) -> LoadUpcomingEventsUseCase {
        LoadUpcomingEventsUseCase(
            authorizer: FakeCalendarAccessAuthorizer(status: status),
            calendarRepository: InMemoryCalendarRepository(
                accounts: accounts ?? [accountA], calendars: calendars ?? [work, personal]
            ),
            eventRepository: events,
            visibilityRepository: InMemoryCalendarVisibilityRepository(visibility: visibility),
            exclusionRepository: InMemoryCountdownExclusionRepository(exclusions: exclusions),
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

    @Test func 辞退した予定を除き重複を一つにする() async throws {
        let events = RecordingEventRepository(events: [
            Fixtures.event("declined", calendar: "work", hour: 13, attendance: .declined),
            Fixtures.event("a", calendar: "work", hour: 14, uid: "same"),
            Fixtures.event("b", calendar: "work", account: accountB, hour: 14, uid: "same"),
        ])
        let work2 = Fixtures.userCalendar("work", account: accountB)
        let upcoming = try await makeUseCase(
            accounts: [accountA, accountB], calendars: [work, work2], events: events
        ).execute()
        #expect(upcoming.events.map(\.eventID.rawValue) == ["a"])
    }

    @Test func 除外の集合を一緒に返し残り時間の計算に使える() async throws {
        let first = Fixtures.event("first", calendar: "work", hour: 13)
        let second = Fixtures.event("second", calendar: "work", hour: 15)
        var exclusions = CountdownExclusions()
        exclusions.exclude(first.id, start: Fixtures.date(2026, 10, 24, 13))
        let upcoming = try await makeUseCase(events: RecordingEventRepository(events: [first, second]), exclusions: exclusions)
            .execute()
        #expect(upcoming.exclusions == exclusions)
        #expect(upcoming.countdown(at: now)?.remainingMinutes == 180)
    }
}

@Suite struct SetCountdownExclusionUseCaseTests {
    let account = SampleData.googleAccount.id
    let now = SampleData.now

    func identity(_ id: String) -> CalendarEvent.Identity {
        CalendarEvent.Identity(
            accountID: account, calendarID: try! CalendarID("work"), eventID: try! EventID(id)
        )
    }

    @Test func 除外して戻せる() async throws {
        let repository = InMemoryCountdownExclusionRepository()
        let useCase = SetCountdownExclusionUseCase(repository: repository, dateProvider: FixedDateProvider())
        let start = now.addingTimeInterval(3600)
        try await useCase.execute(event: identity("a"), start: start, isExcluded: true)
        #expect(await repository.load().isExcluded(identity("a")))
        try await useCase.execute(event: identity("a"), start: start, isExcluded: false)
        #expect(await !repository.load().isExcluded(identity("a")))
    }

    @Test func 保存するとき開始が現在より前の項目を消す() async throws {
        var initial = CountdownExclusions()
        initial.exclude(identity("past"), start: now.addingTimeInterval(-1))
        initial.exclude(identity("future"), start: now.addingTimeInterval(60))
        let repository = InMemoryCountdownExclusionRepository(exclusions: initial)
        let useCase = SetCountdownExclusionUseCase(repository: repository, dateProvider: FixedDateProvider())
        try await useCase.execute(event: identity("new"), start: now.addingTimeInterval(3600), isExcluded: true)
        let saved = await repository.load()
        #expect(!saved.isExcluded(identity("past")))
        #expect(saved.isExcluded(identity("future")))
        #expect(saved.isExcluded(identity("new")))
    }

    @Test func 保存に失敗したら投げて変更を保存しない() async {
        struct SaveFailure: Error {}
        let repository = InMemoryCountdownExclusionRepository(error: SaveFailure())
        let useCase = SetCountdownExclusionUseCase(repository: repository, dateProvider: FixedDateProvider())
        await #expect(throws: SaveFailure.self) {
            try await useCase.execute(event: identity("a"), start: now.addingTimeInterval(3600), isExcluded: true)
        }
        #expect(await repository.load() == CountdownExclusions())
    }

    @Test func 読み込みは保存した集合を返す() async {
        var initial = CountdownExclusions()
        initial.exclude(identity("a"), start: now.addingTimeInterval(60))
        let useCase = LoadCountdownExclusionsUseCase(repository: InMemoryCountdownExclusionRepository(exclusions: initial))
        #expect(await useCase.execute() == initial)
    }
}
