/// 曜日。`rawValue` は `Calendar.firstWeekday` と同じ値で、1 が日曜、7 が土曜である。
public enum Weekday: Int, CaseIterable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}
