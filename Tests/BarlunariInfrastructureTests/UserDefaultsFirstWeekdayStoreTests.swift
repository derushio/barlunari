import BarlunariApplication
import BarlunariDomain
import Foundation
import Testing
@testable import BarlunariInfrastructure

/// 一意の suiteName の `UserDefaults` を作り、テスト後に消す。
private func withIsolatedDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let suiteName = "barlunari.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    return try body(defaults)
}

@Suite struct UserDefaultsFirstWeekdayStoreTests {
    @Test func 保存がなければnilを返す() {
        withIsolatedDefaults { defaults in
            #expect(UserDefaultsFirstWeekdayStore(defaults: defaults).load() == nil)
        }
    }

    @Test(arguments: Weekday.allCases) func 保存した曜日を別のインスタンスから読み戻せる(weekday: Weekday) {
        withIsolatedDefaults { defaults in
            UserDefaultsFirstWeekdayStore(defaults: defaults).save(weekday)
            #expect(UserDefaultsFirstWeekdayStore(defaults: defaults).load() == weekday)
        }
    }

    @Test func 後から保存した曜日で上書きする() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsFirstWeekdayStore(defaults: defaults)
            store.save(.monday)
            store.save(.saturday)
            #expect(store.load() == .saturday)
        }
    }

    @Test func nilを保存すると保存を消す() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsFirstWeekdayStore(defaults: defaults)
            store.save(.monday)
            store.save(nil)
            #expect(store.load() == nil)
            #expect(defaults.object(forKey: UserDefaultsFirstWeekdayStore.key) == nil)
        }
    }

    @Test(arguments: [0, 8, -1]) func 範囲外の整数が保存されていたらnilを返す(value: Int) {
        withIsolatedDefaults { defaults in
            defaults.set(value, forKey: UserDefaultsFirstWeekdayStore.key)
            #expect(UserDefaultsFirstWeekdayStore(defaults: defaults).load() == nil)
        }
    }

    @Test func 整数でない値が保存されていたらnilを返す() {
        withIsolatedDefaults { defaults in
            defaults.set("monday", forKey: UserDefaultsFirstWeekdayStore.key)
            #expect(UserDefaultsFirstWeekdayStore(defaults: defaults).load() == nil)
        }
    }
}
