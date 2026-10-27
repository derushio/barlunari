import MenuDateDomain

/// ある範囲の予定表と、月表示のドットに使う日ごとの色。
public struct AgendaSnapshot: Sendable, Equatable {
    public let days: [DayAgenda]
    /// 日ごとの、予定があるカレンダーの色。重複は除き、その日の予定の並び順で最初に現れた順に並べる。
    public let colorsByDay: [CalendarDay: [CalendarColor]]
    /// 予定の取得に使った、表示中のカレンダー。`days` の予定の `calendarIdentity` から引ける。
    public let calendars: [UserCalendar]
    /// `calendars` を持つアカウント。予定の詳細にアカウントの名前を出すために使う。
    public let accounts: [UserAccount]

    public init(
        days: [DayAgenda],
        colorsByDay: [CalendarDay: [CalendarColor]],
        calendars: [UserCalendar] = [],
        accounts: [UserAccount] = []
    ) {
        self.days = days
        self.colorsByDay = colorsByDay
        self.calendars = calendars
        self.accounts = accounts
    }

    public static let empty = AgendaSnapshot(days: [], colorsByDay: [:])

    public func calendar(for id: UserCalendar.Identity) -> UserCalendar? {
        calendars.first { $0.id == id }
    }

    public func account(for id: AccountID) -> UserAccount? {
        accounts.first { $0.id == id }
    }
}
