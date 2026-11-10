import Foundation
import BarlunariApplication
import BarlunariDomain
import Synchronization

/// 残り時間の対象にするかの設定（アカウント・カレンダー・予定の ID の組と、対象にするかの真偽）を `UserDefaults` に JSON で保存する。
///
/// 以前の形式（`countdownExclusions`、対象から外した予定の ID の組と開始日時）が残っていれば、
/// 「対象外」を選んだ設定として引き継ぐ。新しい形式を書き出したら、古いキーを消す。
/// `update` の読み込みから保存までをロックで直列化するため、他の更新は割り込まない。
public final class UserDefaultsCountdownTargetSettingsRepository: CountdownTargetSettingsRepository {
    static let key = "countdownTargets"
    /// 以前の形式のキー。読み込みの移行元で、新しい形式を書き出すときに消す。
    static let legacyKey = "countdownExclusions"

    private struct Record: Codable, Comparable {
        let accountID: String
        let calendarID: String
        let eventID: String
        let isTarget: Bool

        static func < (lhs: Record, rhs: Record) -> Bool {
            (lhs.accountID, lhs.calendarID, lhs.eventID) < (rhs.accountID, rhs.calendarID, rhs.eventID)
        }
    }

    /// 以前の形式の項目。開始日時は使わない。
    private struct LegacyRecord: Decodable {
        let accountID: String
        let calendarID: String
        let eventID: String
    }

    // UserDefaults はスレッドセーフだが Sendable と宣言されていないため、ここで安全性を保証する。
    private nonisolated(unsafe) let defaults: UserDefaults
    private let lock = Mutex(())

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() async -> CountdownTargetSettings {
        lock.withLock { _ in read() }
    }

    public func update(_ body: @Sendable (inout CountdownTargetSettings) -> Void) async {
        lock.withLock { _ in
            var settings = read()
            body(&settings)
            let records = settings.choices
                .map { id, isTarget in
                    Record(
                        accountID: id.accountID.rawValue, calendarID: id.calendarID.rawValue,
                        eventID: id.eventID.rawValue, isTarget: isTarget
                    )
                }
                .sorted()
            // 構造体の配列の符号化は失敗しない。
            defaults.set(try? JSONEncoder().encode(records), forKey: Self.key)
            defaults.removeObject(forKey: Self.legacyKey)
        }
    }

    private func identity(_ accountID: String, _ calendarID: String, _ eventID: String) -> CalendarEvent.Identity? {
        // 空の ID は作れない。壊れた項目は読み飛ばし、その予定は既定の値に戻す。
        guard let accountID = try? AccountID(accountID),
              let calendarID = try? CalendarID(calendarID),
              let eventID = try? EventID(eventID)
        else { return nil }
        return CalendarEvent.Identity(accountID: accountID, calendarID: calendarID, eventID: eventID)
    }

    private func read() -> CountdownTargetSettings {
        if let data = defaults.data(forKey: Self.key) {
            let records = (try? JSONDecoder().decode([Record].self, from: data)) ?? []
            var choices: [CalendarEvent.Identity: Bool] = [:]
            for record in records {
                guard let id = identity(record.accountID, record.calendarID, record.eventID) else { continue }
                choices[id] = record.isTarget
            }
            return CountdownTargetSettings(choices: choices)
        }
        guard let data = defaults.data(forKey: Self.legacyKey),
              let records = try? JSONDecoder().decode([LegacyRecord].self, from: data)
        else { return CountdownTargetSettings() }
        var choices: [CalendarEvent.Identity: Bool] = [:]
        for record in records {
            guard let id = identity(record.accountID, record.calendarID, record.eventID) else { continue }
            choices[id] = false
        }
        return CountdownTargetSettings(choices: choices)
    }
}
