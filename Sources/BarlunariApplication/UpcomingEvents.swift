import Foundation
import BarlunariDomain

/// これから始まる予定と、残り時間の対象から外した予定。メニューバーの残り時間の計算に使う。
public struct UpcomingEvents: Sendable, Equatable {
    /// 表示するカレンダーの予定。重複と辞退した予定は除いてある。取得した範囲に重なる予定である。
    public let events: [CalendarEvent]
    public let exclusions: CountdownExclusions
    /// 取得した範囲の終わり。これより後に始まる予定は `events` に入っていない。
    public let rangeEnd: Date

    public init(events: [CalendarEvent], exclusions: CountdownExclusions, rangeEnd: Date) {
        self.events = events
        self.exclusions = exclusions
        self.rangeEnd = rangeEnd
    }

    /// `now` の時点で、次の予定までの残り時間。対象がなければ `nil`。
    public func countdown(at now: Date) -> NextEventCountdown? {
        NextEventCountdown.next(in: events, excluding: exclusions, at: now)
    }
}
