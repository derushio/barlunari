import Foundation
import BarlunariDomain

/// これから始まる予定と、残り時間の対象にするかの判定。メニューバーの残り時間の計算に使う。
public struct UpcomingEvents: Sendable, Equatable {
    /// 表示するカレンダーの予定。重複は除いてある。辞退した予定も含む（`countdown(at:)` が数えない）。取得した範囲に重なる予定である。
    public let events: [CalendarEvent]
    public let policy: CountdownTargetPolicy
    /// 取得した範囲の終わり。これより後に始まる予定は `events` に入っていない。
    public let rangeEnd: Date
    /// 予定の開始日時を求める暦。
    public let calendar: Calendar

    public init(events: [CalendarEvent], policy: CountdownTargetPolicy, rangeEnd: Date, calendar: Calendar) {
        self.events = events
        self.policy = policy
        self.rangeEnd = rangeEnd
        self.calendar = calendar
    }

    /// `now` の時点で、次の予定までの残り時間。対象がなければ `nil`。
    public func countdown(at now: Date) -> NextEventCountdown? {
        NextEventCountdown.next(in: events, policy: policy, at: now, calendar: calendar)
    }
}
