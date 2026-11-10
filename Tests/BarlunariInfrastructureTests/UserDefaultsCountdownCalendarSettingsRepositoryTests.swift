import Foundation
import BarlunariApplication
import BarlunariDomain
import Testing
@testable import BarlunariInfrastructure

/// 一意の suiteName の `UserDefaults` を作り、テスト後に消す。
private func withIsolatedDefaults<T>(_ body: (UserDefaults) async throws -> T) async rethrows -> T {
    let suiteName = "barlunari.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    return try await body(defaults)
}

@Suite struct UserDefaultsCountdownCalendarSettingsRepositoryTests {
    private func identity(_ account: AccountID, _ calendar: String) throws -> UserCalendar.Identity {
        UserCalendar.Identity(accountID: account, calendarID: try CalendarID(calendar))
    }

    @Test func 保存がなければすべて含める() async {
        await withIsolatedDefaults { defaults in
            let settings = await UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults).load()
            #expect(settings.excludedCalendars.isEmpty)
        }
    }

    @Test func 保存した含めないカレンダーの集合を読み戻せる() async throws {
        let first = try identity(TestAccount.a.id, "first@example.com")
        let second = try identity(TestAccount.a.id, "second")
        let other = try identity(TestAccount.a.id, "other")
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults)
            await repository.update {
                $0.exclude(first)
                $0.exclude(second)
            }

            let loaded = await UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults).load()
            #expect(loaded.excludedCalendars == [first, second])
            #expect(!loaded.isIncluded(first))
            #expect(loaded.isIncluded(other))
        }
    }

    @Test func 同じカレンダーIDでもアカウントごとに保存する() async throws {
        let holidayA = try identity(TestAccount.a.id, "holiday")
        let holidayB = try identity(TestAccount.b.id, "holiday")
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults)
            await repository.update { $0.exclude(holidayA) }

            let loaded = await UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults).load()
            #expect(!loaded.isIncluded(holidayA))
            #expect(loaded.isIncluded(holidayB))
        }
    }

    @Test func 含めるに戻すと保存からも消える() async throws {
        let id = try identity(TestAccount.a.id, "a")
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults)
            await repository.update { $0.exclude(id) }
            await repository.update { $0.include(id) }
            #expect(await repository.load().excludedCalendars.isEmpty)
        }
    }

    @Test func 予定ごとの設定とは別のキーに保存し互いに影響しない() async throws {
        let id = try identity(TestAccount.a.id, "a")
        #expect(UserDefaultsCountdownCalendarSettingsRepository.key == "countdownExcludedCalendars")
        #expect(UserDefaultsCountdownCalendarSettingsRepository.key != UserDefaultsCountdownTargetSettingsRepository.key)
        await withIsolatedDefaults { defaults in
            let targets = UserDefaultsCountdownTargetSettingsRepository(defaults: defaults)
            let eventID = CalendarEvent.Identity(accountID: id.accountID, calendarID: id.calendarID, eventID: try! EventID("e"))
            await targets.update { $0.set(eventID, isTarget: false) }
            let calendars = UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults)
            await calendars.update { $0.exclude(id) }
            await calendars.update { $0.include(id) }

            #expect(await targets.load().choice(for: eventID) == false)
            #expect(defaults.data(forKey: UserDefaultsCountdownTargetSettingsRepository.key) != nil)
        }
    }

    @Test func 壊れた保存値は読み飛ばしてすべて含める() async {
        await withIsolatedDefaults { defaults in
            let key = UserDefaultsCountdownCalendarSettingsRepository.key
            defaults.set(Data("not json".utf8), forKey: key)
            #expect(await UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults).load().excludedCalendars.isEmpty)
            defaults.set(Data(#"[{"accountID":"","calendarID":"x"},{"accountID":"a","calendarID":"y"}]"#.utf8), forKey: key)
            let loaded = await UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults).load()
            #expect(loaded.excludedCalendars.map(\.calendarID.rawValue) == ["y"])
        }
    }

    @Test func 同時に切り替えても両方の変更が残る() async throws {
        let ids = try (0..<50).map { try identity(TestAccount.a.id, "calendar-\($0)") }
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownCalendarSettingsRepository(defaults: defaults)
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask { await repository.update { $0.exclude(id) } }
                }
            }
            #expect(await repository.load().excludedCalendars == Set(ids))
        }
    }
}
