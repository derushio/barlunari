import Foundation
import MenuDateApplication
import MenuDateDomain
import MenuDatePreviewSupport

enum Fixtures {
    static var calendar: Calendar { SampleData.calendar }

    static func calendarID(_ value: String) -> CalendarID { try! CalendarID(value) }
    static func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { SampleData.day(y, m, d) }
    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date { SampleData.date(y, m, d, h, 0) }

    static let accountA = SampleData.googleAccount
    static let accountB = SampleData.workAccount

    static func userCalendar(_ id: String, account: UserAccount = accountA, hex: String = "#336699") -> UserCalendar {
        UserCalendar(accountID: account.id, id: calendarID(id), name: id, color: try! CalendarColor(hex: hex))
    }

    static func event(
        _ id: String, calendar calendarID: String, account: UserAccount = accountA, hour: Int, title: String? = nil,
        attendance: AttendanceStatus = .accepted, uid: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            accountID: account.id, id: try! EventID(id), calendarID: Self.calendarID(calendarID), title: title ?? id,
            schedule: .timed(DateInterval(start: date(2026, 10, 24, hour), duration: 3600)),
            attendance: attendance, iCalendarUID: uid
        )
    }

    static func oneDay(_ day: CalendarDay) -> DayRange {
        try! DayRange(start: day, dayCount: 1, calendar: calendar)
    }
}

/// 呼び出しを記録する予定のリポジトリ。渡された予定を、要求されたカレンダーのものだけ返す。
actor RecordingEventRepository: CalendarEventRepository {
    private let base: InMemoryCalendarEventRepository
    private(set) var requestedCalendars: [Set<UserCalendar.Identity>] = []
    private(set) var requestedIntervals: [DateInterval] = []

    init(events: [CalendarEvent] = [], error: (any Error)? = nil) {
        base = InMemoryCalendarEventRepository(events: events, error: error)
    }

    func events(in interval: DateInterval, calendars: Set<UserCalendar.Identity>) async throws -> [CalendarEvent] {
        requestedCalendars.append(calendars)
        requestedIntervals.append(interval)
        return try await base.events(in: interval, calendars: calendars)
    }
}

/// `update` の呼び出し回数を数える表示設定のリポジトリ。まとめての切り替えが 1 回の `update` で行われることを確かめる。
actor CountingVisibilityRepository: CalendarVisibilityRepository {
    private var visibility: CalendarVisibility
    private(set) var updateCount = 0

    init(visibility: CalendarVisibility = CalendarVisibility()) {
        self.visibility = visibility
    }

    func load() async -> CalendarVisibility { visibility }

    func update(_ body: @Sendable (inout CalendarVisibility) -> Void) async {
        updateCount += 1
        body(&visibility)
    }
}
