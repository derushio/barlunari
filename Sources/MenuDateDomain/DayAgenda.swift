/// ある日の予定の一覧。並び順は `AgendaBuilder` が保証する。
public struct DayAgenda: Sendable, Hashable, Identifiable {
    public let day: CalendarDay
    public let events: [CalendarEvent]

    public var id: CalendarDay { day }

    public init(day: CalendarDay, events: [CalendarEvent]) {
        self.day = day
        self.events = events
    }

    /// `Hashable` の既定は `events` の同一性だけを見るため、並び順の違いも検出できるよう ID 列で比較する。
    public static func == (lhs: DayAgenda, rhs: DayAgenda) -> Bool {
        lhs.day == rhs.day && lhs.events.map(\.id) == rhs.events.map(\.id)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(day)
        hasher.combine(events.map(\.id))
    }
}
