import MenuDateApplication

/// 予定を表示できないときに、利用者に次の操作を案内する状態。ポップオーバーと設定画面で共有する。
public enum CalendarAccessGuide: Equatable, Sendable {
    /// まだ許可を求めていない。ボタンで許可を求める。
    case notDetermined
    /// 許可されていない。システム設定のプライバシーの画面を開く。
    case denied
    /// カレンダーが 1 つもない。「インターネットアカウント」を開く。
    case noCalendars

    init(_ error: CalendarAccessError) {
        switch error {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .noCalendars: self = .noCalendars
        }
    }

    public var message: String {
        switch self {
        case .notDetermined:
            "カレンダーの予定を表示するには、カレンダーへのアクセスを許可してください。"
        case .denied:
            "カレンダーへのアクセスが許可されていません。システム設定のプライバシーとセキュリティで、MenuDate にカレンダーのフルアクセスを許可してください。"
        case .noCalendars:
            "表示できるカレンダーがありません。システム設定の「インターネットアカウント」でアカウントを追加すると、カレンダーが表示されます。"
        }
    }

    public var buttonTitle: String {
        switch self {
        case .notDetermined: "カレンダーへのアクセスを許可"
        case .denied: "システム設定を開く"
        case .noCalendars: "「インターネットアカウント」を開く"
        }
    }
}
