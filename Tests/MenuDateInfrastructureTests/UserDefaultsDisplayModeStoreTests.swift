import Foundation
import MenuDateApplication
import Testing
@testable import MenuDateInfrastructure

/// 一意の suiteName の `UserDefaults` を作り、テスト後に消す。
private func withIsolatedDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let suiteName = "menudate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    return try body(defaults)
}

@Suite struct UserDefaultsDisplayModeStoreTests {
    @Test func 保存がなければnilを返す() {
        withIsolatedDefaults { defaults in
            #expect(UserDefaultsDisplayModeStore(defaults: defaults).load() == nil)
        }
    }

    @Test(arguments: CalendarDisplayMode.allCases) func 保存したモードを別のインスタンスから読み戻せる(mode: CalendarDisplayMode) {
        withIsolatedDefaults { defaults in
            UserDefaultsDisplayModeStore(defaults: defaults).save(mode)
            #expect(UserDefaultsDisplayModeStore(defaults: defaults).load() == mode)
        }
    }

    @Test func 後から保存した値で上書きする() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsDisplayModeStore(defaults: defaults)
            store.save(.compact)
            store.save(.month)
            #expect(store.load() == .month)
        }
    }

    @Test func 知らない値が保存されていたらnilを返す() {
        withIsolatedDefaults { defaults in
            defaults.set("week", forKey: UserDefaultsDisplayModeStore.key)
            #expect(UserDefaultsDisplayModeStore(defaults: defaults).load() == nil)
        }
    }

    @Test func 文字列でない値が保存されていたらnilを返す() {
        withIsolatedDefaults { defaults in
            defaults.set(1, forKey: UserDefaultsDisplayModeStore.key)
            #expect(UserDefaultsDisplayModeStore(defaults: defaults).load() == nil)
        }
    }
}
