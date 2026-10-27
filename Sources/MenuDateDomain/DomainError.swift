/// 値オブジェクトの生成時に不変条件が破れたことを表す。
public enum DomainError: Error, Equatable, Sendable {
    case invalidDay(year: Int, month: Int, day: Int)
    case invalidMonth(year: Int, month: Int)
    case emptyDayRange
    case invalidWeekday(Int)
    case emptyIdentifier
    case emptyAccountName
    case invalidColor(String)
    case participantWithoutNameOrEmail
}
