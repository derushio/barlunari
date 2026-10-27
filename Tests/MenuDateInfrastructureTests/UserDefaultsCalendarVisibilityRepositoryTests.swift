import Foundation
import MenuDateApplication
import MenuDateDomain
import Testing
@testable import MenuDateInfrastructure

/// 一意の suiteName の `UserDefaults` を作り、テスト後に消す。
private func withIsolatedDefaults<T>(_ body: (UserDefaults) async throws -> T) async rethrows -> T {
    let suiteName = "menudate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    return try await body(defaults)
}

@Suite struct UserDefaultsCalendarVisibilityRepositoryTests {
    private func identity(_ account: AccountID, _ calendar: String) throws -> UserCalendar.Identity {
        UserCalendar.Identity(accountID: account, calendarID: try CalendarID(calendar))
    }

    @Test func 保存がなければすべて表示する() async {
        await withIsolatedDefaults { defaults in
            let visibility = await UserDefaultsCalendarVisibilityRepository(defaults: defaults).load()
            #expect(visibility.hiddenCalendars.isEmpty)
        }
    }

    @Test func 保存した非表示の集合を読み戻せる() async throws {
        let hidden = try identity(TestAccount.a.id, "hidden@example.com")
        let holiday = try identity(TestAccount.a.id, "ja.japanese#holiday@group.v.calendar.google.com")
        let other = try identity(TestAccount.a.id, "other")
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCalendarVisibilityRepository(defaults: defaults)
            await repository.update {
                $0.hide(hidden)
                $0.hide(holiday)
            }

            let loaded = await UserDefaultsCalendarVisibilityRepository(defaults: defaults).load()
            #expect(loaded.hiddenCalendars == [hidden, holiday])
            #expect(!loaded.isVisible(hidden))
            #expect(loaded.isVisible(other))
        }
    }

    @Test func 同じカレンダーIDでもアカウントごとに保存する() async throws {
        let holidayA = try identity(TestAccount.a.id, "holiday")
        let holidayB = try identity(TestAccount.b.id, "holiday")
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCalendarVisibilityRepository(defaults: defaults)
            await repository.update { $0.hide(holidayA) }

            let loaded = await UserDefaultsCalendarVisibilityRepository(defaults: defaults).load()
            #expect(!loaded.isVisible(holidayA))
            #expect(loaded.isVisible(holidayB))
        }
    }

    @Test func 表示に戻すと保存からも消える() async throws {
        let id = try identity(TestAccount.a.id, "a")
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCalendarVisibilityRepository(defaults: defaults)
            await repository.update { $0.hide(id) }
            await repository.update { $0.show(id) }
            #expect(await repository.load().hiddenCalendars.isEmpty)
        }
    }

    @Test func アカウントを持たない古い形式の項目は読まずに削除する() async {
        await withIsolatedDefaults { defaults in
            defaults.set(["old@example.com"], forKey: UserDefaultsCalendarVisibilityRepository.legacyKey)
            let loaded = await UserDefaultsCalendarVisibilityRepository(defaults: defaults).load()
            #expect(loaded.hiddenCalendars.isEmpty)
            #expect(defaults.object(forKey: UserDefaultsCalendarVisibilityRepository.legacyKey) == nil)
        }
    }

    @Test func 壊れた保存値は読み飛ばしてすべて表示する() async {
        await withIsolatedDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: UserDefaultsCalendarVisibilityRepository.key)
            #expect(await UserDefaultsCalendarVisibilityRepository(defaults: defaults).load().hiddenCalendars.isEmpty)
            defaults.set(
                Data(#"[{"accountID":"","calendarID":"x"},{"accountID":"a","calendarID":"y"}]"#.utf8),
                forKey: UserDefaultsCalendarVisibilityRepository.key
            )
            let loaded = await UserDefaultsCalendarVisibilityRepository(defaults: defaults).load()
            #expect(loaded.hiddenCalendars.map(\.calendarID.rawValue) == ["y"])
        }
    }
}

@Suite struct 表示設定の同時更新Tests {
    @Test func 同時に切り替えても両方の変更が残る() async throws {
        let ids = try (0..<50).map { UserCalendar.Identity(accountID: TestAccount.a.id, calendarID: try CalendarID("calendar-\($0)")) }
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCalendarVisibilityRepository(defaults: defaults)
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask { await repository.update { $0.hide(id) } }
                }
            }
            #expect(await repository.load().hiddenCalendars == Set(ids))
        }
    }
}
