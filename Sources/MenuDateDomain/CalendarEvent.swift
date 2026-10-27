import Foundation

/// カレンダーの予定。同一性は `AccountID`、`CalendarID`、`EventID` の組で判定する。
public struct CalendarEvent: Sendable, Hashable, Identifiable {
    /// 予定 ID はカレンダーをまたいで重複しうるため、カレンダー ID と組にして同一性を表す。
    /// 共有カレンダーの予定は複数のアカウントから取得されるため、アカウントも含める。
    public struct Identity: Sendable, Hashable {
        public let accountID: AccountID
        public let calendarID: CalendarID
        public let eventID: EventID
    }

    /// 複数のアカウントが同じ予定を取得したとき、同じ予定とみなす組。`AgendaBuilder` が重複の除去に使う。
    ///
    /// 繰り返しの予定はすべての回が同じ UID を持つため、日時と組にして回を区別する。
    public struct SharedKey: Sendable, Hashable {
        public let iCalendarUID: String
        public let schedule: EventSchedule
    }

    public let accountID: AccountID
    public let eventID: EventID
    public let calendarID: CalendarID
    public let title: String
    public let schedule: EventSchedule
    public let location: String?
    public let meetingURL: URL?
    public let detailURL: URL?
    /// メモ。前後の空白を取り除いて空なら `nil` にする。
    public let notes: String?
    /// 主催者を先頭に置く。同じ参加者は 1 人にまとめて渡す。
    public let participants: [EventParticipant]
    public let attendance: AttendanceStatus
    /// iCalendar の UID。持たない予定は `nil`。前後の空白を取り除いて空なら `nil` にする。
    public let iCalendarUID: String?

    public var id: Identity { Identity(accountID: accountID, calendarID: calendarID, eventID: eventID) }
    public var calendarIdentity: UserCalendar.Identity { UserCalendar.Identity(accountID: accountID, calendarID: calendarID) }
    /// UID を持たない予定は `nil`。同じ予定かどうかを判定できないため、重複の除去の対象にならない。
    public var sharedKey: SharedKey? {
        iCalendarUID.map { SharedKey(iCalendarUID: $0, schedule: schedule) }
    }

    public init(
        accountID: AccountID,
        id eventID: EventID,
        calendarID: CalendarID,
        title: String,
        schedule: EventSchedule,
        location: String? = nil,
        meetingURL: URL? = nil,
        detailURL: URL? = nil,
        notes: String? = nil,
        participants: [EventParticipant] = [],
        attendance: AttendanceStatus = .notApplicable,
        iCalendarUID: String? = nil
    ) {
        self.accountID = accountID
        self.eventID = eventID
        self.calendarID = calendarID
        self.title = title
        self.schedule = schedule
        self.location = location
        self.meetingURL = meetingURL
        self.detailURL = detailURL
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = trimmedNotes.flatMap { $0.isEmpty ? nil : $0 }
        self.participants = participants
        self.attendance = attendance
        let trimmedUID = iCalendarUID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.iCalendarUID = trimmedUID.flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
