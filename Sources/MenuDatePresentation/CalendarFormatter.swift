import Foundation
import MenuDateApplication
import MenuDateDomain

/// 画面に出す日付と時刻の書式。
///
/// タイムゾーンは `Calendar` のものを使い、ロケールは `ja_JP` に固定する。
/// システムのロケールに依存すると曜日の表記が変わり、画面の幅が崩れるため。
struct CalendarFormatter {
    let calendar: Calendar
    private let monthTitleFormatter: DateFormatter
    private let dayHeaderFormatter: DateFormatter
    private let timeFormatter: DateFormatter

    /// `Calendar.firstWeekday` が 1（日曜）のときの並び。
    private static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    init(calendar: Calendar) {
        self.calendar = calendar
        func make(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = format
            return formatter
        }
        monthTitleFormatter = make("yyyy年M月")
        dayHeaderFormatter = make("M月d日(E)")
        timeFormatter = make("H:mm")
    }

    func monthTitle(_ month: CalendarMonth) -> String {
        monthTitleFormatter.string(from: month.firstDay.startDate(in: calendar))
    }

    /// 例は `10月24日(土)`。
    func dayHeader(_ day: CalendarDay) -> String {
        dayHeaderFormatter.string(from: day.startDate(in: calendar))
    }

    func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// 予定の日時。例は `10月24日(土) 14:00〜15:30`、`10月29日(木) 23:00〜10月30日(金) 6:30`、`10月27日(火)〜10月29日(木) 終日`。
    func scheduleText(_ schedule: EventSchedule) -> String {
        switch schedule {
        case .allDay(let range):
            // 終日予定の終了日は排他的なので、最終日は 1 日前になる。
            let lastDay = range.end.adding(days: -1, calendar: calendar)
            let first = dayHeader(range.start)
            return lastDay == range.start ? "\(first) 終日" : "\(first)〜\(dayHeader(lastDay)) 終日"
        case .timed(let interval):
            let startDay = CalendarDay(date: interval.start, calendar: calendar)
            let endDay = CalendarDay(date: interval.end, calendar: calendar)
            let start = "\(dayHeader(startDay)) \(time(interval.start))"
            if interval.duration == 0 { return start }
            return startDay == endDay
                ? "\(start)〜\(time(interval.end))"
                : "\(start)〜\(dayHeader(endDay)) \(time(interval.end))"
        }
    }

    /// 週の開始曜日から並べた曜日の記号。
    func weekdaySymbolsFromFirstWeekday() -> [String] {
        let offset = calendar.firstWeekday - 1
        return Array(Self.weekdaySymbols[offset...] + Self.weekdaySymbols[..<offset])
    }

    /// 1 が日曜、7 が土曜。
    func weekday(of day: CalendarDay) -> Int {
        calendar.component(.weekday, from: day.startDate(in: calendar))
    }
}

/// `DateProvider` の現在の暦に合った `CalendarFormatter` を返す。
///
/// 週の開始曜日やタイムゾーンは起動中に変わるため、`init` 時点の暦を保持しない。
/// 暦が変わっていないあいだは `DateFormatter` を作り直さない。
@MainActor
final class CurrentCalendarFormatter {
    private let dateProvider: any DateProvider
    private var cached: CalendarFormatter?
    /// 日の見出し。暦が変わるまで、同じ日の見出しを書式から作り直さない。マス目の行が表示月の変更のたびに読むため。
    private var dayHeaders: [CalendarDay: String] = [:]

    init(dateProvider: any DateProvider) {
        self.dateProvider = dateProvider
    }

    var formatter: CalendarFormatter {
        let calendar = dateProvider.calendar
        if let cached, cached.calendar == calendar { return cached }
        let formatter = CalendarFormatter(calendar: calendar)
        cached = formatter
        dayHeaders.removeAll()
        return formatter
    }

    /// 現在の暦での日の見出し。例は `10月24日(土)`。
    func dayHeader(_ day: CalendarDay) -> String {
        let current = formatter
        if let header = dayHeaders[day] { return header }
        let header = current.dayHeader(day)
        dayHeaders[day] = header
        return header
    }
}
