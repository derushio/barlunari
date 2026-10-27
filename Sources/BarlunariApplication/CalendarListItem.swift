import BarlunariDomain

public struct CalendarListItem: Sendable, Equatable, Identifiable {
    public let calendar: UserCalendar
    public let isVisible: Bool

    public var id: UserCalendar.Identity { calendar.id }

    public init(calendar: UserCalendar, isVisible: Bool) {
        self.calendar = calendar
        self.isVisible = isVisible
    }

    /// `UserCalendar` の `==` は ID しか見ないため、表示状態の変化を検出できるよう属性も比べる。
    public static func == (lhs: CalendarListItem, rhs: CalendarListItem) -> Bool {
        lhs.isVisible == rhs.isVisible
            && lhs.calendar.id == rhs.calendar.id
            && lhs.calendar.name == rhs.calendar.name
            && lhs.calendar.color == rhs.calendar.color
    }
}

/// 設定画面に出す、アカウントとカレンダーの一覧。
public struct CalendarList: Sendable, Equatable {
    /// アカウントの並び順。カレンダーを持たないアカウントは含まない。
    public let accounts: [UserAccount]
    public let items: [CalendarListItem]

    public init(accounts: [UserAccount], items: [CalendarListItem]) {
        self.accounts = accounts
        self.items = items
    }
}
