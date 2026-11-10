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

@Suite struct UserDefaultsCountdownExclusionRepositoryTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000.5)

    private func identity(_ account: AccountID, _ event: String, calendar: String = "work") throws -> CalendarEvent.Identity {
        CalendarEvent.Identity(accountID: account, calendarID: try CalendarID(calendar), eventID: try EventID(event))
    }

    @Test func 保存がなければ何も除外しない() async {
        await withIsolatedDefaults { defaults in
            #expect(await UserDefaultsCountdownExclusionRepository(defaults: defaults).load() == CountdownExclusions())
        }
    }

    @Test func 保存した除外を開始日時とともに読み戻せる() async throws {
        let id = try identity(TestAccount.a.id, "event-1")
        await withIsolatedDefaults { defaults in
            await UserDefaultsCountdownExclusionRepository(defaults: defaults).update { $0.exclude(id, start: start) }
            let loaded = await UserDefaultsCountdownExclusionRepository(defaults: defaults).load()
            #expect(loaded.isExcluded(id))
            #expect(loaded.starts[id] == start)
        }
    }

    @Test func 同じ予定IDでもアカウントとカレンダーごとに保存する() async throws {
        let a = try identity(TestAccount.a.id, "event-1")
        let b = try identity(TestAccount.b.id, "event-1")
        let other = try identity(TestAccount.a.id, "event-1", calendar: "personal")
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownExclusionRepository(defaults: defaults)
            await repository.update { $0.exclude(a, start: start) }
            let loaded = await repository.load()
            #expect(loaded.isExcluded(a))
            #expect(!loaded.isExcluded(b))
            #expect(!loaded.isExcluded(other))
        }
    }

    @Test func 戻すと保存からも消える() async throws {
        let id = try identity(TestAccount.a.id, "event-1")
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownExclusionRepository(defaults: defaults)
            await repository.update { $0.exclude(id, start: start) }
            await repository.update { $0.include(id) }
            #expect(await repository.load() == CountdownExclusions())
        }
    }

    @Test func 壊れた保存値は読み飛ばして何も除外しない() async {
        await withIsolatedDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: UserDefaultsCountdownExclusionRepository.key)
            #expect(await UserDefaultsCountdownExclusionRepository(defaults: defaults).load() == CountdownExclusions())
            defaults.set(
                Data(#"[{"accountID":"","calendarID":"x","eventID":"e","start":1},{"accountID":"a","calendarID":"y","eventID":"e2","start":2}]"#.utf8),
                forKey: UserDefaultsCountdownExclusionRepository.key
            )
            let loaded = await UserDefaultsCountdownExclusionRepository(defaults: defaults).load()
            #expect(loaded.starts.keys.map(\.eventID.rawValue) == ["e2"])
        }
    }

    @Test func 同時に更新しても変更が残る() async throws {
        let ids = try (0..<50).map { try identity(TestAccount.a.id, "event-\($0)") }
        await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownExclusionRepository(defaults: defaults)
            let start = start
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask { await repository.update { $0.exclude(id, start: start) } }
                }
            }
            #expect(Set(await repository.load().starts.keys) == Set(ids))
        }
    }
}
