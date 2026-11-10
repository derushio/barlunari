import Foundation

/// メニューバーの残り時間の対象にするかを、利用者が予定ごとに選んだ値の集約ルート。
///
/// 予定の同一性（`CalendarEvent.Identity`）と、対象にするかの真偽の組を持つ。
/// 繰り返しの予定は回ごとに ID が異なるので、設定は回ごとになる。
/// 選んでいない予定は、既定の値に従う。既定は、時刻付きの予定は対象、終日の予定は対象外である。
/// カレンダーごとの設定は `CountdownCalendarSettings` が別に持ち、合わせた判定は `CountdownTargetPolicy` が行う。
/// 参加状況（辞退など）は、この設定にも既定の値にも影響しない。辞退した予定を残り時間に数えないのは `NextEventCountdown` が決める。
public struct CountdownTargetSettings: Sendable, Hashable {
    /// 利用者が選んだ値。選んでいない予定は持たない。
    public private(set) var choices: [CalendarEvent.Identity: Bool]

    public init(choices: [CalendarEvent.Identity: Bool] = [:]) {
        self.choices = choices
    }

    /// 選んでいない予定の既定の値。時刻付きは対象、終日は対象外。
    public static func isTargetByDefault(_ schedule: EventSchedule) -> Bool {
        !schedule.isAllDay
    }

    /// 利用者が選んだ値。選んでいなければ `nil`。
    public func choice(for id: CalendarEvent.Identity) -> Bool? {
        choices[id]
    }

    /// 予定を対象にするか対象外にするかを選ぶ。
    public mutating func set(_ id: CalendarEvent.Identity, isTarget: Bool) {
        choices[id] = isTarget
    }
}
