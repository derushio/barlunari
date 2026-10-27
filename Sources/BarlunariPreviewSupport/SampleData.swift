import Foundation
import BarlunariDomain

/// プレビューとスナップショット用のサンプル。基準日は固定で、描画結果が実行日に左右されない。
///
/// 値はすべてリテラルから作るため、生成の失敗はプログラミングエラーとして扱い `try!` を使う。
public enum SampleData {
    public static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 1
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }()

    /// 2026-10-24（土）12:00 JST
    public static let now: Date = date(2026, 10, 24, 12, 0)
    public static let today: CalendarDay = day(2026, 10, 24)

    /// 名前の順に並べる。重複の除去では、先のアカウントの予定が残る。
    public static let googleAccount = try! UserAccount(id: accountID("account-google"), name: "Google")
    public static let workAccount = try! UserAccount(id: accountID("account-work"), name: "仕事")
    public static let accounts: [UserAccount] = [googleAccount, workAccount]

    public static let personalCalendar = UserCalendar(
        accountID: googleAccount.id, id: calendarID("calendar-google-personal"),
        name: "プライベート", color: color("#0B8043")
    )
    public static let holidayCalendar = UserCalendar(
        accountID: googleAccount.id, id: calendarID("calendar-google-holiday"), name: "日本の祝日", color: color("#D50000")
    )
    public static let workCalendar = UserCalendar(
        accountID: workAccount.id, id: calendarID("calendar-work"),
        name: "仕事", color: color("#4285F4")
    )
    /// `holidayCalendar` と同じ祝日を、別のアカウントが別のカレンダーとして持つ。予定の UID は同じになる。
    public static let workAccountHolidayCalendar = UserCalendar(
        accountID: workAccount.id, id: calendarID("calendar-work-holiday"), name: "日本の祝日", color: color("#D50000")
    )
    public static let calendars: [UserCalendar] = [
        personalCalendar, holidayCalendar, workCalendar, workAccountHolidayCalendar,
    ]

    public static let events: [CalendarEvent] = [
        timed("standup", workCalendar, "朝会", (2026, 10, 24, 10, 0), (2026, 10, 24, 10, 15),
              meeting: "https://meet.google.com/abc-defg-hij"),
        timed("design-review", workCalendar, "デザインレビュー", (2026, 10, 24, 14, 0), (2026, 10, 24, 15, 30),
              location: "会議室 A", meeting: "https://meet.google.com/xyz-uvwx-rst",
              detail: "https://example.com/events/design-review", attendance: .accepted,
              notes: designReviewNotes, participants: designReviewParticipants),
        timed("dinner", personalCalendar, "夕食", (2026, 10, 24, 19, 0), (2026, 10, 24, 21, 0),
              location: "渋谷", detail: "https://example.com/events/dinner"),
        allDay("moving-day", personalCalendar, "引っ越し", from: day(2026, 10, 25), days: 1),
        timed("1on1", workCalendar, "1on1", (2026, 10, 26, 11, 0), (2026, 10, 26, 11, 30),
              meeting: "https://meet.google.com/one-on-one", attendance: .tentative),
        allDay("offsite", workCalendar, "開発合宿", from: day(2026, 10, 27), days: 3),
        timed("night-bus", personalCalendar, "夜行バス", (2026, 10, 29, 23, 0), (2026, 10, 30, 6, 30)),
        allDay("culture-day", holidayCalendar, "文化の日", from: day(2026, 11, 3), days: 1),
        allDay("culture-day", workAccountHolidayCalendar, "文化の日", from: day(2026, 11, 3), days: 1),
        timed("declined", workCalendar, "辞退した会議", (2026, 10, 24, 16, 0), (2026, 10, 24, 17, 0),
              attendance: .declined),
    ]

    /// 月表示の確認用。`events` に加えて、1 日のマスに入りきらない日、週をまたぐ終日予定、日をまたぐ時刻付きの予定、長いタイトルの予定を持つ。
    public static let monthViewEvents: [CalendarEvent] = events + [
        timed("busy-1", workCalendar, "朝会", (2026, 10, 22, 9, 0), (2026, 10, 22, 9, 15)),
        timed("busy-2", workCalendar, "仕様の確認", (2026, 10, 22, 10, 0), (2026, 10, 22, 11, 0)),
        timed("busy-3", personalCalendar, "歯医者", (2026, 10, 22, 12, 0), (2026, 10, 22, 13, 0)),
        timed("busy-4", workCalendar, "レビュー", (2026, 10, 22, 14, 0), (2026, 10, 22, 15, 0)),
        timed("busy-5", workCalendar, "採用面談", (2026, 10, 22, 16, 0), (2026, 10, 22, 17, 0)),
        timed("busy-6", personalCalendar, "ジム", (2026, 10, 22, 19, 0), (2026, 10, 22, 20, 0)),
        allDay("trip", personalCalendar, "出張", from: day(2026, 10, 30), days: 4),
        timed("workshop", workCalendar, "社外ワークショップ", (2026, 10, 20, 15, 0), (2026, 10, 21, 11, 0)),
        timed("long-title", workCalendar, "第 3 四半期の全社会議に向けた事前資料の読み合わせと論点整理", (2026, 10, 28, 13, 0), (2026, 10, 28, 14, 0)),
        // 日の欄の確認用。10 月 23 日に、時間軸で重なる予定（3 列になるまとまりと 2 列になるまとまり）、短い予定、終日の予定を持つ。
        allDay("overlap-allday", holidayCalendar, "創立記念日", from: day(2026, 10, 23), days: 1),
        timed("overlap-1", workCalendar, "週次定例", (2026, 10, 23, 10, 0), (2026, 10, 23, 11, 0)),
        timed("overlap-2", workCalendar, "障害対応", (2026, 10, 23, 10, 30), (2026, 10, 23, 12, 0)),
        timed("overlap-3", personalCalendar, "確認", (2026, 10, 23, 10, 45), (2026, 10, 23, 11, 0)),
        timed("overlap-4", personalCalendar, "ランチ", (2026, 10, 23, 12, 0), (2026, 10, 23, 13, 0)),
        timed("overlap-5", workCalendar, "設計会議", (2026, 10, 23, 15, 0), (2026, 10, 23, 16, 30)),
        timed("overlap-6", personalCalendar, "電話", (2026, 10, 23, 16, 0), (2026, 10, 23, 16, 10)),
    ]

    /// `denseEvents(in:)` を、月のマス目が表示できる全日（基準日から決まる `WeekTimeline.selectableDayRange`）に作る。
    public static let denseMonthViewEvents: [CalendarEvent] = {
        let timeline = try! WeekTimeline(today: today, firstWeekday: calendar.firstWeekday)
        return denseEvents(in: timeline.selectableDayRange)
    }()

    /// 予定の多いカレンダーの確認用。`range` の全日に時刻付きの予定を 3〜8 件（日によって変える）、
    /// 週ごとに終日の予定と複数日の予定を 2〜3 件持つ。長いタイトルも混ぜる。カレンダーは `calendars` を使う。
    ///
    /// 日と週の番号だけから決まるので、同じ `range` なら同じ予定を返す。
    public static func denseEvents(in range: DayRange) -> [CalendarEvent] {
        let days = range.days(calendar: calendar)
        var result: [CalendarEvent] = []
        for (dayIndex, day) in days.enumerated() {
            let count = denseTimedCount(dayIndex: dayIndex)
            for slot in 0..<count {
                let start = calendar.date(
                    bySettingHour: 7 + slot * 2, minute: ((dayIndex + slot) % 4) * 15, second: 0, of: day.startDate(in: calendar)
                )!
                let minutes = [30, 45, 60, 90][(dayIndex + slot * 3) % 4]
                result.append(denseEvent(
                    "dense-\(dayIndex)-\(slot)", denseTitles[(dayIndex * 3 + slot) % denseTitles.count],
                    owner: calendars[(dayIndex + slot) % calendars.count],
                    schedule: .timed(DateInterval(start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60))))
                ))
            }
        }
        // 週ごとの予定。週は範囲の最初の日から 7 日ごとに数え、週の境目をまたぐ予定も混ぜる。
        for week in 0..<(days.count + 6) / 7 {
            let weekStart = week * 7
            func allDayEvent(_ name: String, title: String, offset: Int, length: Int, owner: UserCalendar) {
                let startIndex = weekStart + offset
                guard startIndex < days.count else { return }
                result.append(denseEvent(
                    "dense-week-\(week)-\(name)", title, owner: owner,
                    schedule: .allDay(try! DayRange(start: days[startIndex], dayCount: length, calendar: calendar))
                ))
            }
            allDayEvent("single", title: denseAllDayTitles[week % denseAllDayTitles.count], offset: (week * 3) % 7, length: 1, owner: holidayCalendar)
            allDayEvent("multi", title: denseAllDayTitles[(week + 2) % denseAllDayTitles.count], offset: (week * 2 + 1) % 7, length: 2 + week % 3, owner: calendars[(week + 1) % calendars.count])
            if week % 2 == 0, weekStart + 4 < days.count {
                let start = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: days[weekStart + 4].startDate(in: calendar))!
                result.append(denseEvent(
                    "dense-week-\(week)-overnight", "泊まりがけの出張の移動と宿泊の手配の確認", owner: workCalendar,
                    schedule: .timed(DateInterval(start: start, end: start.addingTimeInterval(TimeInterval(30 * 3600))))
                ))
            }
        }
        return result
    }

    /// 日の番号から決まる時刻付きの予定の件数。3〜8 件。
    static func denseTimedCount(dayIndex: Int) -> Int { 3 + (dayIndex * 5 + dayIndex / 3) % 6 }

    private static let denseTitles = [
        "朝会", "1on1", "デザインレビュー", "仕様の確認", "ランチ", "採用面談", "週次の定例", "歯医者",
        "第 3 四半期の全社会議に向けた事前資料の読み合わせと論点整理", "顧客への提案内容のすり合わせ",
        "Weekly Product Sync with the Platform Engineering and Design Teams", "ジム",
    ]

    private static let denseAllDayTitles = ["開発合宿", "出張", "休暇", "リリース週間", "社内イベント", "研修"]

    private static func denseEvent(_ id: String, _ title: String, owner: UserCalendar, schedule: EventSchedule) -> CalendarEvent {
        CalendarEvent(
            accountID: owner.accountID, id: try! EventID(id), calendarID: owner.calendarID, title: title,
            schedule: schedule, attendance: .accepted, iCalendarUID: "\(id)@example.com"
        )
    }

    private static let designReviewNotes = """
        議題
        ・デザインシステムの更新内容の確認
        ・次回リリースに含める画面の優先順位

        事前に資料を確認してください。資料: https://example.com/docs/design-review-2026-10
        """

    private static let designReviewParticipants: [EventParticipant] = [
        participant("山田 太郎", "yamada@example.com", .accepted, isOrganizer: true),
        participant("佐藤 花子", "sato@example.com", .accepted, isCurrentUser: true),
        participant("鈴木 一郎", "suzuki@example.com", .tentative),
        participant(nil, "tanaka@example.com", .needsAction),
        participant("高橋 美咲", "takahashi@example.com", .declined),
        participant("伊藤 健", nil, .notApplicable),
    ]

    public static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        try! CalendarDay(year: year, month: month, day: day)
    }

    public static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private typealias DateTuple = (Int, Int, Int, Int, Int)

    private static func participant(
        _ name: String?, _ emailAddress: String?, _ attendance: AttendanceStatus,
        isOrganizer: Bool = false, isCurrentUser: Bool = false
    ) -> EventParticipant {
        try! EventParticipant(
            name: name, emailAddress: emailAddress, attendance: attendance,
            isOrganizer: isOrganizer, isCurrentUser: isCurrentUser
        )
    }

    private static func accountID(_ value: String) -> AccountID { try! AccountID(value) }
    private static func calendarID(_ value: String) -> CalendarID { try! CalendarID(value) }
    private static func color(_ hex: String) -> CalendarColor { try! CalendarColor(hex: hex) }

    private static func timed(
        _ id: String, _ owner: UserCalendar, _ title: String, _ start: DateTuple, _ end: DateTuple,
        location: String? = nil, meeting: String? = nil, detail: String? = nil,
        attendance: AttendanceStatus = .accepted,
        notes: String? = nil, participants: [EventParticipant] = []
    ) -> CalendarEvent {
        CalendarEvent(
            accountID: owner.accountID, id: try! EventID(id), calendarID: owner.calendarID, title: title,
            schedule: .timed(DateInterval(
                start: date(start.0, start.1, start.2, start.3, start.4),
                end: date(end.0, end.1, end.2, end.3, end.4)
            )),
            location: location,
            meetingURL: meeting.flatMap(URL.init(string:)),
            detailURL: detail.flatMap(URL.init(string:)),
            notes: notes,
            participants: participants,
            attendance: attendance,
            iCalendarUID: "\(id)@example.com"
        )
    }

    private static func allDay(
        _ id: String, _ owner: UserCalendar, _ title: String, from start: CalendarDay, days: Int
    ) -> CalendarEvent {
        CalendarEvent(
            accountID: owner.accountID, id: try! EventID(id), calendarID: owner.calendarID, title: title,
            schedule: .allDay(try! DayRange(start: start, dayCount: days, calendar: calendar)),
            attendance: .notApplicable,
            iCalendarUID: "\(id)@example.com"
        )
    }
}
