/// カレンダーへのアクセスの許可の状態。
///
/// 書き込みだけの許可と制限は、予定を読めないため `denied` として扱う。
public enum CalendarAuthorizationStatus: Sendable, Equatable {
    /// 利用者がまだ許可も拒否もしていない。この状態のときだけ、許可を求められる。
    case notDetermined
    case denied
    case fullAccess

    /// 完全アクセスでなければ、状態に対応する `CalendarAccessError` を投げる。
    func requireFullAccess() throws {
        switch self {
        case .notDetermined: throw CalendarAccessError.notDetermined
        case .denied: throw CalendarAccessError.denied
        case .fullAccess: break
        }
    }
}
