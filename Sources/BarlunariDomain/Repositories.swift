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

/// メニューバーの残り時間の対象にするかの設定の保存先。
public protocol CountdownTargetSettingsRepository: Sendable {
    func load() async -> CountdownTargetSettings

    /// 保存済みの集約を読み、`body` で変更して保存するまでを原子的に行う。
    ///
    /// 同時に呼ばれても、互いの変更を失わない。読んでから書くまでの間に他の更新が割り込まないよう、
    /// 実装は呼び出しを直列化する。保存に失敗したら投げ、そのときは変更を保存しない。
    func update(_ body: @Sendable (inout CountdownTargetSettings) -> Void) async throws
}

/// メニューバーの残り時間に含めないカレンダーの設定の保存先。予定ごとの設定（`CountdownTargetSettingsRepository`）とは別に持つ。
public protocol CountdownCalendarSettingsRepository: Sendable {
    func load() async -> CountdownCalendarSettings

    /// 保存済みの集約を読み、`body` で変更して保存するまでを原子的に行う。
    ///
    /// 同時に呼ばれても、互いの変更を失わない。保存に失敗したら投げ、そのときは変更を保存しない。
    func update(_ body: @Sendable (inout CountdownCalendarSettings) -> Void) async throws
}
