import Foundation
import BarlunariApplication

/// 「辞退した予定を表示」を `UserDefaults` に真偽値で保存する。
public final class UserDefaultsShowDeclinedEventsStore: ShowDeclinedEventsStore {
    static let key = "showDeclinedEvents"

    // UserDefaults はスレッドセーフだが Sendable と宣言されていないため、ここで安全性を保証する。
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `bool(forKey:)` は未保存を `false` にするため、`object(forKey:)` で未保存と区別する。
    public func load() -> Bool? {
        defaults.object(forKey: Self.key) as? Bool
    }

    public func save(_ show: Bool) {
        defaults.set(show, forKey: Self.key)
    }
}
