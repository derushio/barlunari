/// 予定をメニューバーの残り時間の対象にするかを、予定ごとの選択とカレンダーごとの設定を合わせて決める値。
///
/// 終日の予定は、予定ごとの選択とカレンダーの設定にかかわらず、常に対象外である（`canBeTarget(_:)`）。
/// 終日以外の予定の優先順位は次のとおり。
/// 1. 利用者が予定ごとに選んだ値（`CountdownTargetSettings`）
/// 2. 予定のカレンダーの設定（`CountdownCalendarSettings`）。含めないカレンダーの予定は対象外
/// 3. 既定の値。時刻付きは対象
///
/// 参加状況（辞退など）は、この型の判定に影響しない。辞退した予定を残り時間に数えないのは `NextEventCountdown` が決める。
public struct CountdownTargetPolicy: Sendable, Hashable {
    public private(set) var events: CountdownTargetSettings
    public private(set) var calendars: CountdownCalendarSettings

    public init(
        events: CountdownTargetSettings = CountdownTargetSettings(),
        calendars: CountdownCalendarSettings = CountdownCalendarSettings()
    ) {
        self.events = events
        self.calendars = calendars
    }

    /// 予定が残り時間の対象になりうるか。終日の予定は、選択や設定にかかわらず `false`。
    public func canBeTarget(_ event: CalendarEvent) -> Bool {
        !event.schedule.isAllDay
    }

    /// 予定ごとの選択がないときの値。対象になりえない予定と、含めないカレンダーの予定は対象外、それ以外は予定の種類の既定の値。
    public func isTargetByDefault(_ event: CalendarEvent) -> Bool {
        canBeTarget(event)
            && calendars.isIncluded(event.calendarIdentity)
            && CountdownTargetSettings.isTargetByDefault(event.schedule)
    }

    /// 予定を残り時間の対象にするか。対象になりえない予定は `false`。それ以外は、予定ごとの選択があればそれ、なければ `isTargetByDefault(_:)`。
    public func isTarget(_ event: CalendarEvent) -> Bool {
        guard canBeTarget(event) else { return false }
        return events.choice(for: event.id) ?? isTargetByDefault(event)
    }

    /// 予定を対象にするか対象外にするかを、予定ごとの選択として持つ。
    public mutating func choose(_ id: CalendarEvent.Identity, isTarget: Bool) {
        events.set(id, isTarget: isTarget)
    }
}
