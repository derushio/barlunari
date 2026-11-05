import Foundation

/// 標準のカレンダーアプリで予定を開く URL。書式はカレンダーアプリ自身が持つ `ical://ekevent/%@?method=show&options=more`。
enum CalendarAppURL {
    /// - Parameters:
    ///   - calendarItemIdentifier: `EKEvent.calendarItemIdentifier`。
    ///   - startDate: 表示している回の開始日時。繰り返しの予定のときだけ URL に入れる。
    ///   - isAllDay: 終日の予定は、`calendar` のタイムゾーンで日付を書式化する。時刻付きの予定は UTC。
    ///   - hasRecurrenceRules: 繰り返しの予定か。
    ///   - calendar: アプリの暦。終日の予定の日付のタイムゾーンに使う。
    static func url(
        calendarItemIdentifier: String,
        startDate: Date,
        isAllDay: Bool,
        hasRecurrenceRules: Bool,
        calendar: Calendar
    ) -> URL? {
        guard let identifier = calendarItemIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !identifier.isEmpty
        else { return nil }
        var path = identifier
        if hasRecurrenceRules {
            path = "\(startText(of: startDate, isAllDay: isAllDay, calendar: calendar))/\(identifier)"
        }
        return URL(string: "ical://ekevent/\(path)?method=show&options=more")
    }

    /// `yyyyMMdd'T'HHmmss'Z'`。終日の予定でも末尾は `Z` で、日付だけをアプリの暦のタイムゾーンで求める。
    static func startText(of date: Date, isAllDay: Bool, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = isAllDay ? calendar.timeZone : TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
