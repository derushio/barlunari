/// どのカレンダーを表示するかの集約ルート。
///
/// 非表示の集合だけを持つので、新しく追加されたカレンダーは自動的に表示される。
/// 同じ `CalendarID` のカレンダーでも、アカウントごとに別々に管理する。
public struct CalendarVisibility: Sendable, Hashable {
    public private(set) var hiddenCalendars: Set<UserCalendar.Identity>

    public init(hiddenCalendars: Set<UserCalendar.Identity> = []) {
        self.hiddenCalendars = hiddenCalendars
    }

    public func isVisible(_ id: UserCalendar.Identity) -> Bool {
        !hiddenCalendars.contains(id)
    }

    public mutating func hide(_ id: UserCalendar.Identity) {
        hiddenCalendars.insert(id)
    }

    public mutating func show(_ id: UserCalendar.Identity) {
        hiddenCalendars.remove(id)
    }

    /// 複数のカレンダーをまとめて非表示にする。
    public mutating func hide(contentsOf ids: some Sequence<UserCalendar.Identity>) {
        hiddenCalendars.formUnion(ids)
    }

    /// 複数のカレンダーをまとめて表示に戻す。
    public mutating func show(contentsOf ids: some Sequence<UserCalendar.Identity>) {
        hiddenCalendars.subtract(ids)
    }
}
