/// 月のマス目が流れる週の並び。今日を含む週の前後に、固定の数の週を並べる。
///
/// 週は 0 から始まる番号で数える。番号 0 が並びの先頭の週で、`todayWeekIndex` が今日を含む週である。
/// 並びは作ったときに決まり、後から前後に足さない。日の計算は西暦の日数だけで行い、`Calendar` に依存しない。
public struct WeekTimeline: Sendable, Hashable {
    /// 今日を含む週の前後に並べる週の数。前後それぞれ約 1 年分である。
    public static let defaultWeeksOnEachSide = 52
    /// マス目が一度に見せる週の数。
    public static let visibleWeekCount = 6

    public let firstWeekday: Int
    public let weekCount: Int
    public let todayWeekIndex: Int
    private let firstWeekStartNumber: Int
    /// 選べる日の最初の日の `dayNumber`。表示できる最初の月の 1 日。
    private let selectableStartNumber: Int
    /// 選べる日の数。
    private let selectableCount: Int

    /// - Parameters:
    ///   - today: 今日。
    ///   - firstWeekday: 週の開始曜日。`Calendar.firstWeekday` と同じく 1 が日曜、7 が土曜。
    ///   - weeksOnEachSide: 今日を含む週の前後に並べる週の数。対応年の端を越える分は並べない。
    public init(today: CalendarDay, firstWeekday: Int, weeksOnEachSide: Int = Self.defaultWeeksOnEachSide) throws {
        guard (1...7).contains(firstWeekday) else { throw DomainError.invalidWeekday(firstWeekday) }
        let todayNumber = today.dayNumber
        let offset = (Self.weekdayIndex(of: todayNumber) - (firstWeekday - 1) + 7) % 7
        let todayWeekStart = todayNumber - offset
        let earliest = CalendarDay(uncheckedYear: CalendarDay.supportedYears.lowerBound, month: 1, day: 1).dayNumber
        let latest = CalendarDay(uncheckedYear: CalendarDay.supportedYears.upperBound, month: 12, day: 31).dayNumber

        // 先頭の週は、開始日が最初の日以降で、今日の側へ寄せる。末尾の週は、最後の日が最後の日以前に収める。
        let maxBefore = max(0, (todayWeekStart - earliest) / 7)
        let maxAfter = max(0, (latest - (todayWeekStart + 6)) / 7)
        let before = min(max(0, weeksOnEachSide), maxBefore)
        let after = min(max(0, weeksOnEachSide), maxAfter)

        self.firstWeekday = firstWeekday
        self.todayWeekIndex = before
        self.weekCount = before + 1 + after
        self.firstWeekStartNumber = todayWeekStart - 7 * before
        let bounds = Self.selectableBounds(firstWeekStartNumber: todayWeekStart - 7 * before, weekCount: before + 1 + after)
        self.selectableStartNumber = bounds.start
        self.selectableCount = bounds.count
    }

    /// 表示できる最初の月の 1 日から、表示できる最後の月の末日までの日数と最初の日。表示できる月がなければ並び全体。
    private static func selectableBounds(firstWeekStartNumber: Int, weekCount: Int) -> (start: Int, count: Int) {
        let full = (start: firstWeekStartNumber, count: weekCount * 7)
        var first = CalendarDay(dayNumber: firstWeekStartNumber).calendarMonth
        var steps = 0
        while !isShowable(first, firstWeekStartNumber: firstWeekStartNumber, weekCount: weekCount) {
            first = first.next
            steps += 1
            if steps > 3 { return full }
        }
        var last = CalendarDay(dayNumber: firstWeekStartNumber + weekCount * 7 - 1).calendarMonth
        steps = 0
        while !isShowable(last, firstWeekStartNumber: firstWeekStartNumber, weekCount: weekCount) {
            last = last.previous
            steps += 1
            if steps > 3 { return full }
        }
        let start = first.firstDay.dayNumber
        let end = last.firstDay.dayNumber + last.dayCount
        guard start < end else { return full }
        return (start, end - start)
    }

    private static func isShowable(_ month: CalendarMonth, firstWeekStartNumber: Int, weekCount: Int) -> Bool {
        let index = floorDivide(month.firstDay.dayNumber - firstWeekStartNumber, by: 7)
        return index >= 0 && index + visibleWeekCount <= weekCount
    }

    /// 番号の週の最初の日。範囲外なら `nil`。
    public func firstDay(ofWeek index: Int) -> CalendarDay? {
        guard (0..<weekCount).contains(index) else { return nil }
        return CalendarDay(dayNumber: firstWeekStartNumber + 7 * index)
    }

    /// 番号の週の 7 日。範囲外なら空。
    public func days(inWeek index: Int) -> [CalendarDay] {
        guard (0..<weekCount).contains(index) else { return [] }
        let start = firstWeekStartNumber + 7 * index
        return (0..<7).map { CalendarDay(dayNumber: start + $0) }
    }

    /// 選べる日の数。予定一覧が並べる日の数。
    public var dayCount: Int { selectableCount }

    /// 選べる日の最初の日から数えた番号の日。範囲外なら `nil`。予定一覧が日を番号で扱うために使う。
    public func day(at index: Int) -> CalendarDay? {
        guard (0..<selectableCount).contains(index) else { return nil }
        return CalendarDay(dayNumber: selectableStartNumber + index)
    }

    /// `day` の、選べる日の最初の日から数えた番号。選べる日の外なら `nil`。
    public func dayIndex(of day: CalendarDay) -> Int? {
        let index = day.dayNumber - selectableStartNumber
        return (0..<selectableCount).contains(index) ? index : nil
    }

    /// 並びが覆う日の範囲。最初の週の最初の日から、最後の週の最後の日まで。マス目の端の行に見える日を含む。
    public var fullDayRange: DayRange {
        guard let range = dayRange(weeks: 0..<weekCount) else { preconditionFailure("週の並びが空である") }
        return range
    }

    /// 選べる日の範囲。表示できる最初の月の 1 日から、表示できる最後の月の末日まで。予定一覧の日の範囲でもある。
    /// 表示できる月がない短い並びでは、並び全体。
    public var selectableDayRange: DayRange {
        do {
            return try DayRange(
                start: CalendarDay(dayNumber: selectableStartNumber),
                end: CalendarDay(dayNumber: selectableStartNumber + selectableCount)
            )
        } catch {
            preconditionFailure("選べる日の範囲が空である")
        }
    }

    /// `day` を選べるか。マス目が表示できる月の日だけ選べる。
    public func isSelectable(_ day: CalendarDay) -> Bool {
        dayIndex(of: day) != nil
    }

    /// `day` を含む週の番号。並びの外なら `nil`。
    public func weekIndex(containing day: CalendarDay) -> Int? {
        let index = Self.floorDivide(day.dayNumber - firstWeekStartNumber, by: 7)
        return (0..<weekCount).contains(index) ? index : nil
    }

    /// 月の 1 日を含む週の番号。その週を一番上に置いたとき、マス目が見せる週がすべて並びの中に収まる月だけ返す。
    public func firstWeekIndex(of month: CalendarMonth) -> Int? {
        guard Self.isShowable(month, firstWeekStartNumber: firstWeekStartNumber, weekCount: weekCount) else { return nil }
        return weekIndex(containing: month.firstDay)
    }

    /// その月を、マス目で一番上の週を指定して見せられるか。
    public func canShow(_ month: CalendarMonth) -> Bool {
        firstWeekIndex(of: month) != nil
    }

    /// 一番上の週の番号から、マス目の表示月を決める。
    ///
    /// 見えている週の中央、つまり上から 3 行目と 4 行目の境目にある週の、中央の日（週の 4 日目）の月である。
    /// 範囲外の番号は、並びの端の週に丸める。
    public func displayedMonth(topWeek: Int) -> CalendarMonth {
        let center = min(max(topWeek + Self.visibleWeekCount / 2, 0), weekCount - 1)
        let middle = CalendarDay(dayNumber: firstWeekStartNumber + 7 * center + 3)
        return middle.calendarMonth
    }

    /// 週の番号の範囲 `weeks` が覆う日の範囲。並びの外にはみ出す分は切り詰める。重なりがなければ `nil`。
    public func dayRange(weeks: Range<Int>) -> DayRange? {
        let lower = max(weeks.lowerBound, 0)
        let upper = min(weeks.upperBound, weekCount)
        guard lower < upper else { return nil }
        return try? DayRange(
            start: CalendarDay(dayNumber: firstWeekStartNumber + 7 * lower),
            end: CalendarDay(dayNumber: firstWeekStartNumber + 7 * upper)
        )
    }

    /// 1970-01-01（木曜）を基準にした曜日。0 が日曜。
    private static func weekdayIndex(of dayNumber: Int) -> Int {
        ((dayNumber + 4) % 7 + 7) % 7
    }

    private static func floorDivide(_ value: Int, by divisor: Int) -> Int {
        value >= 0 ? value / divisor : -((-value + divisor - 1) / divisor)
    }
}

extension CalendarDay {
    /// 1970-01-01 を 0 とした日数。西暦（グレゴリオ暦）の年月日だけから求める。
    var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = y / 400
        let yearOfEra = y - era * 400
        let monthIndex = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// `dayNumber` の逆。対応年の中の日数だけを渡すこと。
    init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = z / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.init(uncheckedYear: year, month: month, day: day)
    }
}
