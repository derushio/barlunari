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

@Suite struct UserDefaultsCountdownTargetSettingsRepositoryTests {
    private func identity(_ account: AccountID, _ event: String, calendar: String = "work") throws -> CalendarEvent.Identity {
        CalendarEvent.Identity(accountID: account, calendarID: try CalendarID(calendar), eventID: try EventID(event))
    }

    @Test func 保存がなければ何も選んでいない() async {
        await withIsolatedDefaults { defaults in
            #expect(await UserDefaultsCountdownTargetSettingsRepository(defaults: defaults).load() == CountdownTargetSettings())
        }
    }

    @Test func 対象と対象外の両方の選択を読み戻せる() async throws {
        let on = try identity(TestAccount.a.id, "event-on")
        let off = try identity(TestAccount.a.id, "event-off")
        try await withIsolatedDefaults { defaults in
            try await UserDefaultsCountdownTargetSettingsRepository(defaults: defaults).update {
                $0.set(on, isTarget: true)
                $0.set(off, isTarget: false)
            }
            let loaded = await UserDefaultsCountdownTargetSettingsRepository(defaults: defaults).load()
            #expect(loaded.choices[on] == true)
            #expect(loaded.choices[off] == false)
        }
    }

    @Test func 同じ予定IDでもアカウントとカレンダーごとに保存する() async throws {
        let a = try identity(TestAccount.a.id, "event-1")
        let b = try identity(TestAccount.b.id, "event-1")
        let other = try identity(TestAccount.a.id, "event-1", calendar: "personal")
        try await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownTargetSettingsRepository(defaults: defaults)
            try await repository.update { $0.set(a, isTarget: false) }
            let loaded = await repository.load()
            #expect(loaded.choices[a] == false)
            #expect(loaded.choices[b] == nil)
            #expect(loaded.choices[other] == nil)
        }
    }

    @Test func 選び直すと値が上書きされる() async throws {
        let id = try identity(TestAccount.a.id, "event-1")
        try await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownTargetSettingsRepository(defaults: defaults)
            try await repository.update { $0.set(id, isTarget: false) }
            try await repository.update { $0.set(id, isTarget: true) }
            #expect(await repository.load().choices == [id: true])
        }
    }

    @Test func 壊れた保存値は読み飛ばして既定に戻す() async {
        await withIsolatedDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: UserDefaultsCountdownTargetSettingsRepository.key)
            #expect(await UserDefaultsCountdownTargetSettingsRepository(defaults: defaults).load() == CountdownTargetSettings())
            defaults.set(
                Data(#"[{"accountID":"","calendarID":"x","eventID":"e","isTarget":true},{"accountID":"a","calendarID":"y","eventID":"e2","isTarget":false}]"#.utf8),
                forKey: UserDefaultsCountdownTargetSettingsRepository.key
            )
            let loaded = await UserDefaultsCountdownTargetSettingsRepository(defaults: defaults).load()
            #expect(loaded.choices.keys.map(\.eventID.rawValue) == ["e2"])
        }
    }

    @Test func 古いキーの項目を対象外の設定として引き継ぐ() async throws {
        let id = try identity(TestAccount.a.id, "event-1")
        let legacy = #"[{"accountID":"\#(TestAccount.a.id.rawValue)","calendarID":"work","eventID":"event-1","start":800000000.5},{"accountID":"","calendarID":"x","eventID":"e","start":1}]"#
        try await withIsolatedDefaults { defaults in
            defaults.set(Data(legacy.utf8), forKey: UserDefaultsCountdownTargetSettingsRepository.legacyKey)
            let repository = UserDefaultsCountdownTargetSettingsRepository(defaults: defaults)
            #expect(await repository.load().choices == [id: false])
            // 読み込みだけでは書き換えない。
            #expect(defaults.data(forKey: UserDefaultsCountdownTargetSettingsRepository.legacyKey) != nil)
        }
    }

    @Test func 新しい形式を書き出したら古いキーを消し引き継いだ設定を残す() async throws {
        let old = try identity(TestAccount.a.id, "old")
        let new = try identity(TestAccount.a.id, "new")
        let legacy = #"[{"accountID":"\#(TestAccount.a.id.rawValue)","calendarID":"work","eventID":"old","start":1}]"#
        try await withIsolatedDefaults { defaults in
            defaults.set(Data(legacy.utf8), forKey: UserDefaultsCountdownTargetSettingsRepository.legacyKey)
            let repository = UserDefaultsCountdownTargetSettingsRepository(defaults: defaults)
            try await repository.update { $0.set(new, isTarget: true) }
            #expect(defaults.data(forKey: UserDefaultsCountdownTargetSettingsRepository.legacyKey) == nil)
            #expect(await repository.load().choices == [old: false, new: true])
        }
    }

    @Test func 同時に更新しても変更が残る() async throws {
        let ids = try (0..<50).map { try identity(TestAccount.a.id, "event-\($0)") }
        try await withIsolatedDefaults { defaults in
            let repository = UserDefaultsCountdownTargetSettingsRepository(defaults: defaults)
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask { try? await repository.update { $0.set(id, isTarget: false) } }
                }
            }
            #expect(Set(await repository.load().choices.keys) == Set(ids))
        }
    }
}
