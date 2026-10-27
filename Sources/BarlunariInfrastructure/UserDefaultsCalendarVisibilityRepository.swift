import Foundation
import BarlunariDomain
import Synchronization

/// 非表示にしたカレンダー（アカウントと `CalendarID` の組）を `UserDefaults` に JSON で保存する。
///
/// `update` の読み込みから保存までをロックで直列化するため、他の更新は割り込まない。
public final class UserDefaultsCalendarVisibilityRepository: CalendarVisibilityRepository {
    static let key = "hiddenCalendars"
    /// アカウントを持たない形式の古い項目。読まず、削除するだけである。
    static let legacyKey = "hiddenCalendarIDs"

    private struct Record: Codable, Comparable {
        let accountID: String
        let calendarID: String

        static func < (lhs: Record, rhs: Record) -> Bool {
            (lhs.accountID, lhs.calendarID) < (rhs.accountID, rhs.calendarID)
        }
    }

    // UserDefaults はスレッドセーフだが Sendable と宣言されていないため、ここで安全性を保証する。
    private nonisolated(unsafe) let defaults: UserDefaults
    private let lock = Mutex(())

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: Self.legacyKey)
    }

    public func load() async -> CalendarVisibility {
        lock.withLock { _ in read() }
    }

    public func update(_ body: @Sendable (inout CalendarVisibility) -> Void) async {
        lock.withLock { _ in
            var visibility = read()
            body(&visibility)
            let records = visibility.hiddenCalendars
                .map { Record(accountID: $0.accountID.rawValue, calendarID: $0.calendarID.rawValue) }
                .sorted()
            // 構造体の配列の符号化は失敗しない。
            defaults.set(try? JSONEncoder().encode(records), forKey: Self.key)
        }
    }

    private func read() -> CalendarVisibility {
        guard let data = defaults.data(forKey: Self.key),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return CalendarVisibility() }
        // 空の ID は作れない。壊れた値は読み飛ばし、そのカレンダーは表示に戻す。
        let hidden = records.compactMap { record -> UserCalendar.Identity? in
            guard let accountID = try? AccountID(record.accountID), let calendarID = try? CalendarID(record.calendarID)
            else { return nil }
            return UserCalendar.Identity(accountID: accountID, calendarID: calendarID)
        }
        return CalendarVisibility(hiddenCalendars: Set(hidden))
    }
}
