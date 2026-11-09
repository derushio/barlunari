/// 曜日。`rawValue` は `Calendar.firstWeekday` と同じ値で、1 が日曜、7 が土曜である。
public enum Weekday: Int, CaseIterable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    /// `Calendar.firstWeekday` の値から作る。1 から 7 の範囲外なら `DomainError.invalidWeekday` を投げる。
    public init(calendarValue: Int) throws {
        guard let weekday = Weekday(rawValue: calendarValue) else {
            throw DomainError.invalidWeekday(calendarValue)
        }
        self = weekday
    }
}
