import Foundation
import BarlunariDomain

/// 「週の始まり」の保存先。`nil` は「システムの設定に従う」を表す。
///
/// ポップオーバーを開いたときの最初の描画から保存した値で週を並べられるよう、同期の API にする。
public protocol FirstWeekdayStore: Sendable {
    /// 保存した曜日。保存がなければ `nil`（システムの設定に従う）。
    func load() -> Weekday?
    /// 曜日を保存する。`nil` なら保存を消し、システムの設定に従う。
    func save(_ weekday: Weekday?)
}

/// 保存された曜日があれば、`calendar.firstWeekday` をその曜日に置き換える `DateProvider`。
///
/// 保存がなければ、包んだ `DateProvider` の暦をそのまま返す。暦は呼ぶたびに保存を読むので、設定の変更に追従する。
/// 週の開始曜日の上書きは、ここだけで行う。
public struct FirstWeekdayOverridingDateProvider: DateProvider {
    private let base: any DateProvider
    private let store: any FirstWeekdayStore

    public init(base: any DateProvider, store: any FirstWeekdayStore) {
        self.base = base
        self.store = store
    }

    public var now: Date { base.now }

    public var calendar: Calendar {
        var calendar = base.calendar
        if let weekday = store.load() {
            calendar.firstWeekday = weekday.rawValue
        }
        return calendar
    }
}
