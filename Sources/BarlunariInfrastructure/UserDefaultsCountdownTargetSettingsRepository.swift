import Foundation
import BarlunariApplication
import BarlunariDomain
import Synchronization

/// 残り時間の対象から外した予定（アカウント・カレンダー・予定の ID の組と開始日時）を `UserDefaults` に JSON で保存する。
///
/// `update` の読み込みから保存までをロックで直列化するため、他の更新は割り込まない。
public final class UserDefaultsCountdownExclusionRepository: CountdownExclusionRepository {
    static let key = "countdownExclusions"

    private struct Record: Codable, Comparable {
        let accountID: String
        let calendarID: String
        let eventID: String
        /// `Date` の符号化は `timeIntervalSinceReferenceDate` なので、秒の端数も失わない。
        let start: Date

        static func < (lhs: Record, rhs: Record) -> Bool {
            (lhs.accountID, lhs.calendarID, lhs.eventID) < (rhs.accountID, rhs.calendarID, rhs.eventID)
        }
    }

    // UserDefaults はスレッドセーフだが Sendable と宣言されていないため、ここで安全性を保証する。
    private nonisolated(unsafe) let defaults: UserDefaults
    private let lock = Mutex(())

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() async -> CountdownExclusions {
        lock.withLock { _ in read() }
    }

    public func update(_ body: @Sendable (inout CountdownExclusions) -> Void) async {
        lock.withLock { _ in
            var exclusions = read()
            body(&exclusions)
            let records = exclusions.starts
                .map { id, start in
                    Record(
                        accountID: id.accountID.rawValue, calendarID: id.calendarID.rawValue,
                        eventID: id.eventID.rawValue, start: start
                    )
                }
                .sorted()
            // 構造体の配列の符号化は失敗しない。
            defaults.set(try? JSONEncoder().encode(records), forKey: Self.key)
        }
    }

    private func read() -> CountdownExclusions {
        guard let data = defaults.data(forKey: Self.key),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return CountdownExclusions() }
        // 空の ID は作れない。壊れた項目は読み飛ばし、その予定は残り時間の対象に戻す。
        var starts: [CalendarEvent.Identity: Date] = [:]
        for record in records {
            guard let accountID = try? AccountID(record.accountID),
                  let calendarID = try? CalendarID(record.calendarID),
                  let eventID = try? EventID(record.eventID)
            else { continue }
            starts[CalendarEvent.Identity(accountID: accountID, calendarID: calendarID, eventID: eventID)] = record.start
        }
        return CountdownExclusions(starts: starts)
    }
}
