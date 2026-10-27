import Foundation
import BarlunariDomain

/// カレンダーへのアクセスの許可。
public protocol CalendarAccessAuthorizer: Sendable {
    /// 現在の許可の状態。許可を求めることはしない。
    func status() async -> CalendarAuthorizationStatus

    /// 許可を求め、結果の状態を返す。ダイアログは、状態が `notDetermined` のときだけ出る。
    func requestAccess() async throws -> CalendarAuthorizationStatus
}

/// カレンダーのサーバーとの同期を OS に求める。
///
/// 同期の完了は待たない。新しいデータは `Notification.Name.calendarStoreDidChange` で届く。
/// 許可がないときは何もせず、許可のダイアログも出さない。
public protocol CalendarSourceRefresher: Sendable {
    /// サーバーとの同期を OS に求める。新しいデータは `calendarStoreDidChange` で届く。
    func refreshSources() async
}

/// ログイン時にアプリを起動するかの設定。macOS の登録状態を正とし、アプリ側では保持しない。
public protocol LaunchAtLoginService: Sendable {
    func isEnabled() async -> Bool
    func setEnabled(_ enabled: Bool) async throws
}

/// 現在時刻と暦。テストで固定できるよう、直接 `Date()` を呼ばずにここから受け取る。
public protocol DateProvider: Sendable {
    var now: Date { get }
    var calendar: Calendar { get }
}
