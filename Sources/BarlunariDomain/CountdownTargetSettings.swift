import Foundation

/// メニューバーの残り時間の対象にするかを、利用者が予定ごとに選んだ値の集約ルート。
///
/// 予定の同一性（`CalendarEvent.Identity`）と、対象にするかの真偽の組を持つ。
/// 繰り返しの予定は回ごとに ID が異なるので、設定は回ごとになる。
/// 選んでいない予定の既定の値と、選択があっても対象にならない終日の予定の判定は、`CountdownTargetPolicy` が行う。この型は選択を保存済みの値のまま持つ。
/// カレンダーごとの設定は `CountdownCalendarSettings` が別に持ち、合わせた判定は `CountdownTargetPolicy` が行う。
/// 参加状況（辞退など）は、この設定にも既定の値にも影響しない。辞退した予定を残り時間に数えないのは `NextEventCountdown` が決める。
public struct CountdownTargetSettings: Sendable, Hashable {
    /// 利用者が選んだ値。選んでいない予定は持たない。
    public private(set) var choices: [CalendarEvent.Identity: Bool]

    public init(choices: [CalendarEvent.Identity: Bool] = [:]) {
        self.choices = choices
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
