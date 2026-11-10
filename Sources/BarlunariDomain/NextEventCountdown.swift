import Foundation

/// 次の予定の開始までの残り時間。メニューバーの項目に `HH:mm` で出す。
///
/// 対象になる予定は、時刻付きで、開始が現在より後で、自分が辞退しておらず、残り時間の対象から外していないもの。
/// 残りが 24 時間以上先の予定は対象にしない（表示の最大は `23:59`）。終日予定と開始済みの予定も対象にしない。
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

    /// 予定が、日時だけで残り時間の対象になり得るか。時刻付きで、開始が `now` より後で、辞退していない予定。
    ///
    /// 残りが 24 時間以上先の予定も `true` になる。除外の設定を出すかどうかの判定に使う。
    /// 除外しているかどうかは見ない。
    public static func canBeCounted(_ event: CalendarEvent, at now: Date) -> Bool {
        guard case .timed(let interval) = event.schedule else { return false }
        return interval.start > now && event.attendance != .declined
    }

    /// `events` の中で、対象の予定のうち開始が最も早いものまでの残り時間。対象がなければ `nil`。
    public static func next(
        in events: [CalendarEvent],
        excluding exclusions: CountdownExclusions,
        at now: Date
    ) -> NextEventCountdown? {
        var earliest: NextEventCountdown?
        for event in events where canBeCounted(event, at: now) && !exclusions.isExcluded(event.id) {
            guard case .timed(let interval) = event.schedule,
                  let countdown = NextEventCountdown(start: interval.start, now: now)
            else { continue }
            if earliest.map({ countdown.start < $0.start }) ?? true { earliest = countdown }
        }
        return earliest
    }
}
