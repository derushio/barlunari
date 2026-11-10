/// 予定をメニューバーの残り時間の対象にするかを、予定ごとの選択とカレンダーごとの設定を合わせて決める値。
///
/// 優先順位は次のとおり。
/// 1. 利用者が予定ごとに選んだ値（`CountdownTargetSettings`）
/// 2. 予定のカレンダーの設定（`CountdownCalendarSettings`）。含めないカレンダーの予定は対象外
/// 3. 既定の値。時刻付きは対象、終日は対象外
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

    /// 予定ごとの選択がないときの値。カレンダーを含めないなら対象外、含めるなら予定の種類の既定の値。
    public func isTargetByDefault(_ event: CalendarEvent) -> Bool {
        calendars.isIncluded(event.calendarIdentity) && CountdownTargetSettings.isTargetByDefault(event.schedule)
    }

    /// 予定を残り時間の対象にするか。予定ごとの選択があればそれ、なければ `isTargetByDefault(_:)`。
    public func isTarget(_ event: CalendarEvent) -> Bool {
        events.choice(for: event.id) ?? isTargetByDefault(event)
    }

    /// 予定を対象にするか対象外にするかを、予定ごとの選択として持つ。
    public mutating func choose(_ id: CalendarEvent.Identity, isTarget: Bool) {
        events.set(id, isTarget: isTarget)
    }
}
