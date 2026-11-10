import Foundation

/// 次の予定の開始までの残り時間。メニューバーの項目に `HH:mm` で出す。
///
/// 対象になる予定は、`CountdownTargetSettings` で対象になり、開始が現在より後で、残りが 24 時間未満のもの（表示の最大は `23:59`）。
/// 自分が辞退した予定（`attendance == .declined`）は、設定にかかわらず数えない。ほかの参加状況は見ない。終日の予定は、対象にしたときだけ数え、開始はその日の 0:00 とする。
public struct NextEventCountdown: Sendable, Hashable {
    /// 表示する残り時間の上限（分）。これ以上先の予定は対象にしない。
    public static let maximumRemainingMinutes = 24 * 60

    public let start: Date
    /// 開始までの分。秒の端数は切り上げる。開始の直前まで `00:00` にならないよう、最小は 1 である。
    public let remainingMinutes: Int

    /// 表示の `HH` に当たる時間。
    public var hours: Int { remainingMinutes / 60 }
    /// 表示の `mm` に当たる分。
    public var minutes: Int { remainingMinutes % 60 }

    /// 表示が次に変わる時刻。残りの分が 1 つ減る時刻で、残りが 1 分なら開始の時刻である。
    public var nextChange: Date {
        start.addingTimeInterval(-Double(remainingMinutes - 1) * 60)
    }

    /// `start` が `now` の何分前かを求め、対象になるなら値を返す。開始が `now` 以前か、残りが 24 時間以上なら `nil`。
    public init?(start: Date, now: Date) {
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        guard minutes < Self.maximumRemainingMinutes else { return nil }
        self.start = start
        self.remainingMinutes = minutes
    }

    /// 予定の開始日時。時刻付きは開始の時刻、終日は最初の日の 0:00（`calendar` の暦）。
    public static func start(of event: CalendarEvent, calendar: Calendar) -> Date {
        switch event.schedule {
        case .timed(let interval): interval.start
        case .allDay(let range): range.start.startDate(in: calendar)
        }
    }

    /// `events` の中で、`settings` で対象になる予定のうち開始が最も早いものまでの残り時間。対象がなければ `nil`。
    ///
    /// 自分が辞退した予定は、設定にかかわらず数えない。ほかの参加状況は見ない。開始が `now` 以前の予定と、残りが 24 時間以上先の予定は対象にならない。
    public static func next(
        in events: [CalendarEvent],
        settings: CountdownTargetSettings,
        at now: Date,
        calendar: Calendar
    ) -> NextEventCountdown? {
        var earliest: NextEventCountdown?
        for event in events where event.attendance != .declined && settings.isTarget(event) {
            guard let countdown = NextEventCountdown(start: start(of: event, calendar: calendar), now: now)
            else { continue }
            if earliest.map({ countdown.start < $0.start }) ?? true { earliest = countdown }
        }
        return earliest
    }
}
