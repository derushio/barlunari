import Foundation
import BarlunariApplication
import BarlunariDomain

/// 「週の始まり」を `UserDefaults` に整数（`Calendar.firstWeekday` と同じ 1 から 7）で保存する。保存がなければシステムの設定に従う。
public final class UserDefaultsFirstWeekdayStore: FirstWeekdayStore {
    static let key = "firstWeekday"

    // UserDefaults はスレッドセーフだが Sendable と宣言されていないため、ここで安全性を保証する。
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `integer(forKey:)` は未保存を 0 にするため、`object(forKey:)` で未保存と区別する。1 から 7 でない値は読めないものとして `nil` にする。
    public func load() -> Weekday? {
        (defaults.object(forKey: Self.key) as? Int).flatMap(Weekday.init(rawValue:))
    }

    public func save(_ weekday: Weekday?) {
        if let weekday {
            defaults.set(weekday.rawValue, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
