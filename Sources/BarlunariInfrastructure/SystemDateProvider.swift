import Foundation
import BarlunariApplication

/// システムの時計と、利用者のタイムゾーン・週の開始曜日による暦を返す。
public struct SystemDateProvider: DateProvider {
    public init() {}

    public var now: Date { Date() }

    /// `CalendarDay` はグレゴリオ暦を前提とするため、システムの暦が和暦などでもグレゴリオ暦にする。
    /// タイムゾーンと週の開始曜日は呼ぶたびにシステムの設定から読み、設定の変更に追従する。
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.locale = .autoupdatingCurrent
        calendar.firstWeekday = Calendar.autoupdatingCurrent.firstWeekday
        return calendar
    }
}
