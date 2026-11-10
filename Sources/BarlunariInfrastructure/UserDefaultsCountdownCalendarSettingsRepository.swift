import Foundation
import BarlunariDomain
import Synchronization

/// 残り時間に含めないカレンダー（アカウントと `CalendarID` の組）を `UserDefaults` に JSON で保存する。
///
/// 予定ごとの設定（`countdownTargets`）とは別のキーに保存する。
/// `update` の読み込みから保存までをロックで直列化するため、他の更新は割り込まない。
public final class UserDefaultsCountdownCalendarSettingsRepository: CountdownCalendarSettingsRepository {
    static let key = "countdownExcludedCalendars"

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
    }

    public func load() async -> CountdownCalendarSettings {
        lock.withLock { _ in read() }
    }

    public func update(_ body: @Sendable (inout CountdownCalendarSettings) -> Void) async {
        lock.withLock { _ in
            var settings = read()
            body(&settings)
            let records = settings.excludedCalendars
                .map { Record(accountID: $0.accountID.rawValue, calendarID: $0.calendarID.rawValue) }
                .sorted()
            // 構造体の配列の符号化は失敗しない。
            defaults.set(try? JSONEncoder().encode(records), forKey: Self.key)
        }
    }

    private func read() -> CountdownCalendarSettings {
        guard let data = defaults.data(forKey: Self.key),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return CountdownCalendarSettings() }
        // 空の ID は作れない。壊れた値は読み飛ばし、そのカレンダーは含めるに戻す。
        let excluded = records.compactMap { record -> UserCalendar.Identity? in
            guard let accountID = try? AccountID(record.accountID), let calendarID = try? CalendarID(record.calendarID)
            else { return nil }
            return UserCalendar.Identity(accountID: accountID, calendarID: calendarID)
        }
        return CountdownCalendarSettings(excludedCalendars: Set(excluded))
    }
}
