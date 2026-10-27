/// カレンダー取得で起きうる失敗。いずれも、利用者の操作で直せる状態を表す。
public enum CalendarAccessError: Error, Equatable, Sendable {
    /// カレンダーへのアクセスを、利用者がまだ許可も拒否もしていない。
    case notDetermined
    /// カレンダーへのアクセスが許可されていない。書き込みだけの許可と制限も含む。
    case denied
    /// 予定を持てるカレンダーが 1 つもない。macOS の「インターネットアカウント」でアカウントを追加すると直る。
    case noCalendars
}
