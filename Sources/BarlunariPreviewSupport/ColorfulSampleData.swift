import BarlunariDomain
import Foundation

/// 色の見やすさの確認用。明るい色、暗い色、低彩度の色を含む多数のカレンダーと、それぞれの予定を持つ。
///
/// カレンダーの色は、macOS のカレンダーの既定色、Google カレンダーの色、明度や彩度が極端な色から選んだ。
/// `SampleData` の内容は変えず、基準日と暦、アカウントは `SampleData` のものを使う。
public enum ColorfulSampleData {
    /// カレンダーの名前と色。
    static let definitions: [(name: String, hex: String)] = [
        ("明るい黄", "#FFEB3B"), ("薄い水色", "#B3E5FC"), ("暗い紺", "#1A237E"), ("薄いピンク", "#F8BBD0"),
        ("黒に近い色", "#212121"), ("中間の灰色", "#808080"), ("薄い灰色", "#CFD8DC"), ("茶色", "#A2845E"),
        ("オリーブ", "#827717"), ("ティール", "#009688"), ("深い赤", "#B71C1C"), ("蛍光の緑", "#76FF03"),
        ("macOS の赤", "#FF2968"), ("macOS のオレンジ", "#FF9500"), ("macOS の黄", "#FFCC00"), ("macOS の緑", "#63DA38"),
        ("macOS の青", "#1BADF8"), ("macOS の紫", "#CC73E1"), ("Flamingo", "#E67C73"), ("Tangerine", "#F4511E"),
        ("Banana", "#F6BF26"), ("Sage", "#33B679"), ("Basil", "#0B8043"), ("Peacock", "#039BE5"),
        ("Blueberry", "#3F51B5"), ("Lavender", "#7986CB"), ("Grape", "#8E24AA"), ("Graphite", "#616161"),
    ]

    public static let accounts: [UserAccount] = SampleData.accounts

    public static let calendars: [UserCalendar] = definitions.enumerated().map { index, definition in
        UserCalendar(
            accountID: accounts[index % accounts.count].id,
            id: try! CalendarID("colorful-\(index)"),
            name: definition.name,
            color: try! CalendarColor(hex: definition.hex)
        )
    }

    /// 全カレンダーの予定。基準日（10/24 の昼）の前後に散らし、過去の予定（10/24 の昼より前）も含む。
    /// カレンダーごとに、時刻付きの予定を 2 件（基準日と、基準日の前後の日）、終日の予定を 1 件持つ。
    public static let events: [CalendarEvent] = calendars.enumerated().flatMap { index, calendar -> [CalendarEvent] in
        let hour = 8 + index % 11
        let nearDay = SampleData.calendar.date(byAdding: .day, value: index % 9 - 4, to: SampleData.today.startDate(in: SampleData.calendar))!
        let nearDate = SampleData.calendar.startOfDay(for: nearDay)
        let allDayStart = SampleData.calendar.date(byAdding: .day, value: index % 12 - 5, to: SampleData.today.startDate(in: SampleData.calendar))!
        return [
            timed("\(index)-today", calendar, "\(calendar.name)", start: SampleData.date(2026, 10, 24, hour, 0)),
            timed("\(index)-near", calendar, "\(calendar.name)（別の日）", start: nearDate.addingTimeInterval(TimeInterval(hour * 3600))),
            allDay(
                "\(index)-allday", calendar, "\(calendar.name)の終日",
                from: CalendarDay(date: allDayStart, calendar: SampleData.calendar), days: 1 + index % 3
            ),
        ]
    }

    private static func timed(_ id: String, _ owner: UserCalendar, _ title: String, start: Date) -> CalendarEvent {
        CalendarEvent(
            accountID: owner.accountID, id: try! EventID("colorful-\(id)"), calendarID: owner.calendarID, title: title,
            schedule: .timed(DateInterval(start: start, duration: 3600)),
            attendance: .accepted,
            iCalendarUID: "colorful-\(id)@example.com"
        )
    }

    private static func allDay(_ id: String, _ owner: UserCalendar, _ title: String, from start: CalendarDay, days: Int) -> CalendarEvent {
        CalendarEvent(
            accountID: owner.accountID, id: try! EventID("colorful-\(id)"), calendarID: owner.calendarID, title: title,
            schedule: .allDay(try! DayRange(start: start, dayCount: days, calendar: SampleData.calendar)),
            attendance: .notApplicable,
            iCalendarUID: "colorful-\(id)@example.com"
        )
    }
}
