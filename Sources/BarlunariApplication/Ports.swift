import Foundation
import BarlunariDomain

/// カレンダーへのアクセスの許可。
public protocol CalendarAccessAuthorizer: Sendable {
    /// 現在の許可の状態。許可を求めることはしない。
    func status() async -> CalendarAuthorizationStatus

    /// 許可を求め、結果の状態を返す。ダイアログは、状態が `notDetermined` のときだけ出る。
    func requestAccess() async throws -> CalendarAuthorizationStatus
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
