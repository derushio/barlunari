import Foundation
import BarlunariDomain

/// これから始まる予定と、残り時間の対象にするかの設定。メニューバーの残り時間の計算に使う。
public struct UpcomingEvents: Sendable, Equatable {
    /// 表示するカレンダーの予定。重複は除いてある。辞退した予定も含む（`countdown(at:)` が数えない）。取得した範囲に重なる予定である。
    public let events: [CalendarEvent]
    public let settings: CountdownTargetSettings
    /// 取得した範囲の終わり。これより後に始まる予定は `events` に入っていない。
    public let rangeEnd: Date
    /// 終日の予定の開始（その日の 0:00）を求める暦。
    public let calendar: Calendar

    public init(events: [CalendarEvent], settings: CountdownTargetSettings, rangeEnd: Date, calendar: Calendar) {
        self.events = events
        self.settings = settings
        self.rangeEnd = rangeEnd
        self.calendar = calendar
    }

    /// `now` の時点で、次の予定までの残り時間。対象がなければ `nil`。
    public func countdown(at now: Date) -> NextEventCountdown? {
        NextEventCountdown.next(in: events, settings: settings, at: now, calendar: calendar)
    }
}
