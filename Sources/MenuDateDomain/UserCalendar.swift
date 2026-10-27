/// アカウントに属するカレンダー。同一性は `AccountID` と `CalendarID` の組で判定する。
///
/// 共有カレンダーや祝日カレンダーは、複数のアカウントに同じ `CalendarID` で現れる。
public struct UserCalendar: Sendable, Hashable, Identifiable {
    public struct Identity: Sendable, Hashable, Comparable {
        public let accountID: AccountID
        public let calendarID: CalendarID

        public init(accountID: AccountID, calendarID: CalendarID) {
            self.accountID = accountID
            self.calendarID = calendarID
        }

        public static func < (lhs: Identity, rhs: Identity) -> Bool {
            (lhs.accountID, lhs.calendarID) < (rhs.accountID, rhs.calendarID)
        }
    }

    public let accountID: AccountID
    public let calendarID: CalendarID
    public let name: String
    public let color: CalendarColor

    public var id: Identity { Identity(accountID: accountID, calendarID: calendarID) }

    public init(accountID: AccountID, id calendarID: CalendarID, name: String, color: CalendarColor) {
        self.accountID = accountID
        self.calendarID = calendarID
        self.name = name
        self.color = color
    }

    public static func == (lhs: UserCalendar, rhs: UserCalendar) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
