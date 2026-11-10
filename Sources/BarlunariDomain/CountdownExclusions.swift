import Foundation

/// メニューバーの残り時間の対象から外した予定の集約ルート。
///
/// 予定の同一性（`CalendarEvent.Identity`）と、その予定の開始日時の組を持つ。
/// 繰り返しの予定は回ごとに ID が異なるので、除外は回ごとになる。
/// 開始日時は、終わった予定の項目を消すために持つ。
public struct CountdownExclusions: Sendable, Hashable {
    public private(set) var starts: [CalendarEvent.Identity: Date]

    public init(starts: [CalendarEvent.Identity: Date] = [:]) {
        self.starts = starts
    }

    public func isExcluded(_ id: CalendarEvent.Identity) -> Bool {
        starts[id] != nil
    }

    /// 予定を除外する。`start` はその予定の開始日時である。
    public mutating func exclude(_ id: CalendarEvent.Identity, start: Date) {
        starts[id] = start
    }

    /// 予定の除外を取り消す。
    public mutating func include(_ id: CalendarEvent.Identity) {
        starts[id] = nil
    }

    /// 開始日時が `date` より前の項目を消す。終わった予定の項目が増え続けないようにする。
    public mutating func removeEntries(startingBefore date: Date) {
        starts = starts.filter { $0.value >= date }
    }
}
