import Foundation
import BarlunariApplication
import Testing
@testable import BarlunariInfrastructure

/// 一意の suiteName の `UserDefaults` を作り、テスト後に消す。
private func withIsolatedDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let suiteName = "barlunari.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    return try body(defaults)
}

@Suite struct UserDefaultsShowDeclinedEventsStoreTests {
    @Test func 保存がなければnilを返す() {
        withIsolatedDefaults { defaults in
            #expect(UserDefaultsShowDeclinedEventsStore(defaults: defaults).load() == nil)
        }
    }

    @Test(arguments: [true, false]) func 保存した値を別のインスタンスから読み戻せる(value: Bool) {
        withIsolatedDefaults { defaults in
            UserDefaultsShowDeclinedEventsStore(defaults: defaults).save(value)
            #expect(UserDefaultsShowDeclinedEventsStore(defaults: defaults).load() == value)
        }
    }

    @Test func 後から保存した値で上書きする() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsShowDeclinedEventsStore(defaults: defaults)
            store.save(false)
            store.save(true)
            #expect(store.load() == true)
        }
    }

    @Test func 真偽値でない値が保存されていたらnilを返す() {
        withIsolatedDefaults { defaults in
            defaults.set("off", forKey: UserDefaultsShowDeclinedEventsStore.key)
            #expect(UserDefaultsShowDeclinedEventsStore(defaults: defaults).load() == nil)
        }
    }
}
