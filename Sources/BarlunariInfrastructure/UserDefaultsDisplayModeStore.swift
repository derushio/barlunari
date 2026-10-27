import Foundation
import BarlunariApplication

/// 表示モードを `UserDefaults` に文字列で保存する。
public final class UserDefaultsDisplayModeStore: DisplayModeStore {
    static let key = "displayMode"

    // UserDefaults はスレッドセーフだが Sendable と宣言されていないため、ここで安全性を保証する。
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> CalendarDisplayMode? {
        defaults.string(forKey: Self.key).flatMap(CalendarDisplayMode.init(rawValue:))
    }

    public func save(_ mode: CalendarDisplayMode) {
        defaults.set(mode.rawValue, forKey: Self.key)
    }
}
