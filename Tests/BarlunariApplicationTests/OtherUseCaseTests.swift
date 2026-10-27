import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@Suite struct CalendarListUseCaseTests {
    let accountA = Fixtures.accountA
    let accountB = Fixtures.accountB
    let work = Fixtures.userCalendar("work")
    let personal = Fixtures.userCalendar("personal")

    func makeUseCase(
        status: CalendarAuthorizationStatus = .fullAccess,
        accounts: [UserAccount]? = nil,
        calendars: [UserCalendar]? = nil,
        visibility: CalendarVisibility = CalendarVisibility(),
        error: (any Error)? = nil
    ) -> ListCalendarsUseCase {
        ListCalendarsUseCase(
            authorizer: FakeCalendarAccessAuthorizer(status: status),
            calendarRepository: InMemoryCalendarRepository(
                accounts: accounts ?? [accountA], calendars: calendars ?? [work, personal], error: error
            ),
            visibilityRepository: InMemoryCalendarVisibilityRepository(visibility: visibility)
        )
    }

    @Test func アカウントとカレンダーの一覧に表示状態を付ける() async throws {
        var visibility = CalendarVisibility()
        visibility.hide(personal.id)
        let list = try await makeUseCase(visibility: visibility).execute()
        #expect(list.accounts == [accountA])
        #expect(list.items.map(\.id) == [work.id, personal.id])
        #expect(list.items.map(\.isVisible) == [true, false])
    }

    @Test func 同じ名前のカレンダーでもアカウントごとの表示状態を付ける() async throws {
        let holidayA = Fixtures.userCalendar("holiday-a")
        let holidayB = Fixtures.userCalendar("holiday-b", account: accountB)
        var visibility = CalendarVisibility()
        visibility.hide(holidayA.id)
        let list = try await makeUseCase(
            accounts: [accountA, accountB], calendars: [holidayA, holidayB], visibility: visibility
        ).execute()
        #expect(list.accounts == [accountA, accountB])
        #expect(list.items.map(\.isVisible) == [false, true])
    }

    @Test func カレンダーが一つもなければ空の一覧を返す() async throws {
        let list = try await makeUseCase(accounts: [], calendars: []).execute()
        #expect(list.accounts.isEmpty)
        #expect(list.items.isEmpty)
    }

    @Test func 完全アクセスでなければ許可の状態に対応するエラーで失敗する() async {
        await #expect(throws: CalendarAccessError.notDetermined) { try await makeUseCase(status: .notDetermined).execute() }
        await #expect(throws: CalendarAccessError.denied) { try await makeUseCase(status: .denied).execute() }
    }

    @Test func カレンダー一覧の取得の失敗をそのまま投げる() async {
        await #expect(throws: CocoaError(.fileReadUnknown)) {
            try await makeUseCase(error: CocoaError(.fileReadUnknown)).execute()
        }
    }

    @Test func 表示状態の切り替えを保存する() async throws {
        let repository = InMemoryCalendarVisibilityRepository()
        let useCase = SetCalendarVisibilityUseCase(visibilityRepository: repository)

        try await useCase.execute(calendar: work.id, isVisible: false)
        #expect(await repository.load().isVisible(work.id) == false)
        try await useCase.execute(calendar: work.id, isVisible: true)
        #expect(await repository.load().isVisible(work.id))
    }

    @Test func 近い時刻の二つの切り替えが両方残る() async throws {
        let repository = InMemoryCalendarVisibilityRepository()
        let useCase = SetCalendarVisibilityUseCase(visibilityRepository: repository)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await useCase.execute(calendar: work.id, isVisible: false) }
            group.addTask { try await useCase.execute(calendar: personal.id, isVisible: false) }
            try await group.waitForAll()
        }
        #expect(await repository.load().hiddenCalendars == [work.id, personal.id])
    }

    @Test func 複数のカレンダーの切り替えを1回のupdateで保存する() async throws {
        let holiday = Fixtures.userCalendar("holiday")
        let repository = CountingVisibilityRepository(visibility: CalendarVisibility(hiddenCalendars: [holiday.id]))
        let useCase = SetCalendarVisibilityUseCase(visibilityRepository: repository)

        try await useCase.execute(calendars: [work.id, personal.id], isVisible: false)
        #expect(await repository.updateCount == 1)
        #expect(await repository.load().hiddenCalendars == [work.id, personal.id, holiday.id])

        try await useCase.execute(calendars: [work.id, personal.id], isVisible: true)
        #expect(await repository.updateCount == 2)
        #expect(await repository.load().hiddenCalendars == [holiday.id])
    }

    @Test func カレンダー1つの切り替えも1回のupdateで保存する() async throws {
        let repository = CountingVisibilityRepository()
        try await SetCalendarVisibilityUseCase(visibilityRepository: repository)
            .execute(calendar: work.id, isVisible: false)
        #expect(await repository.updateCount == 1)
    }

    @Test func 表示状態を切り替えても他の非表示は残る() async throws {
        let repository = InMemoryCalendarVisibilityRepository(visibility: CalendarVisibility(hiddenCalendars: [personal.id]))
        try await SetCalendarVisibilityUseCase(visibilityRepository: repository)
            .execute(calendar: work.id, isVisible: false)
        #expect(await repository.load().hiddenCalendars == [work.id, personal.id])
    }
}

@Suite struct CalendarAccessUseCaseTests {
    @Test func 許可を求めて結果の状態を返す() async throws {
        let authorizer = FakeCalendarAccessAuthorizer(status: .notDetermined, statusAfterRequest: .fullAccess)
        let status = try await RequestCalendarAccessUseCase(authorizer: authorizer).execute()
        #expect(status == .fullAccess)
        #expect(await authorizer.requestCount == 1)
    }

    @Test func 拒否された結果の状態を返す() async throws {
        let authorizer = FakeCalendarAccessAuthorizer(status: .notDetermined, statusAfterRequest: .denied)
        #expect(try await RequestCalendarAccessUseCase(authorizer: authorizer).execute() == .denied)
    }

    @Test func 許可を求める失敗をそのまま投げる() async {
        let authorizer = FakeCalendarAccessAuthorizer(status: .notDetermined, requestError: CocoaError(.fileReadUnknown))
        await #expect(throws: CocoaError(.fileReadUnknown)) {
            try await RequestCalendarAccessUseCase(authorizer: authorizer).execute()
        }
    }

    @MainActor
    @Test(arguments: [SystemSettingsDestination.calendarPrivacy, .internetAccounts])
    func システム設定の画面を開く(destination: SystemSettingsDestination) {
        let opener = FakeSystemSettingsOpener()
        let opened = OpenSystemSettingsUseCase(opener: opener).execute(destination)
        #expect(opened)
        #expect(opener.openedDestinations == [destination])
    }

    @MainActor
    @Test func システム設定を開けなかったことを返す() {
        let opener = FakeSystemSettingsOpener(result: false)
        #expect(OpenSystemSettingsUseCase(opener: opener).execute(.calendarPrivacy) == false)
    }
}

@Suite struct ログイン時の起動のユースケースTests {
    @Test func 現在の状態を返し変更できる() async throws {
        let service = FakeLaunchAtLoginService(isEnabled: false)
        #expect(await GetLaunchAtLoginUseCase(service: service).execute() == false)
        try await SetLaunchAtLoginUseCase(service: service).execute(enabled: true)
        #expect(await GetLaunchAtLoginUseCase(service: service).execute())
    }
}
