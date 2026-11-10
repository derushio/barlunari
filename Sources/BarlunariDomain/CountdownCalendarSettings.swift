/// メニューバーの残り時間に含めないカレンダーの集約ルート。予定ごとの選択（`CountdownTargetSettings`）とは別に管理する。
///
/// 含めないカレンダーの集合だけを持つので、新しく追加されたカレンダーは自動的に含める。
/// 同じ `CalendarID` のカレンダーでも、アカウントごとに別々に管理する。
/// カレンダーの設定を変えても、予定ごとの選択は変わらない。
public struct CountdownCalendarSettings: Sendable, Hashable {
    public private(set) var excludedCalendars: Set<UserCalendar.Identity>

    public init(excludedCalendars: Set<UserCalendar.Identity> = []) {
        self.excludedCalendars = excludedCalendars
    }

    public func isIncluded(_ id: UserCalendar.Identity) -> Bool {
        !excludedCalendars.contains(id)
    }

    public mutating func exclude(_ id: UserCalendar.Identity) {
        excludedCalendars.insert(id)
    }

    public mutating func include(_ id: UserCalendar.Identity) {
        excludedCalendars.remove(id)
    }
}
