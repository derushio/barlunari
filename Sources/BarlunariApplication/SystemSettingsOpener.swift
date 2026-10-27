/// 開くシステム設定の画面。
public enum SystemSettingsDestination: Sendable, Equatable {
    /// 「プライバシーとセキュリティ」のカレンダー。許可を取り消した利用者が、許可し直すために開く。
    case calendarPrivacy
    /// 「インターネットアカウント」。アカウントの追加と削除は、ここで行う。
    case internetAccounts
}

/// システム設定の画面を開く。
@MainActor
public protocol SystemSettingsOpener: Sendable {
    /// 開けたら `true`。
    @discardableResult
    func open(_ destination: SystemSettingsDestination) -> Bool
}
