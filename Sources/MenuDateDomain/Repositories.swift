import Foundation

public protocol CalendarRepository: Sendable {
    /// 予定のカレンダーを 1 つ以上持つアカウントを返す。名前の順に並べ、同じ名前なら `AccountID` の順にする。
    func accounts() async throws -> [UserAccount]

    /// すべてのアカウントのカレンダーを返す。
    func calendars() async throws -> [UserCalendar]
}

public protocol CalendarEventRepository: Sendable {
    /// `calendars` のカレンダーで、`interval` に重なる予定を返す。
    func events(in interval: DateInterval, calendars: Set<UserCalendar.Identity>) async throws -> [CalendarEvent]
}
public protocol CalendarVisibilityRepository: Sendable {
    func load() async -> CalendarVisibility

    /// 保存済みの集約を読み、`body` で変更して保存するまでを原子的に行う。
    ///
    /// 同時に呼ばれても、互いの変更を失わない。読んでから書くまでの間に他の更新が割り込まないよう、
    /// 実装は呼び出しを直列化する。
    func update(_ body: @Sendable (inout CalendarVisibility) -> Void) async
}
