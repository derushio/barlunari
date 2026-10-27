import Foundation

/// パネルを閉じる理由。
public enum PopoverCloseReason: Equatable, Sendable {
    /// メニューバーのアイコンをもう一度押した。
    case statusItem
    /// パネルが key でなくなった（パネルの外のクリックなど）。
    case focusLoss
    /// 別のアプリが前面になった、または他のアプリのクリック、デスクトップの切り替え。
    case otherApp
    /// Esc。
    case escape
    /// 設定を開いた。
    case openSettings
}

/// Esc を押したときの動き。
public enum PopoverEscapeAction: Equatable, Sendable {
    /// 予定の詳細だけを閉じる。
    case closeDetail
    /// 表示するカレンダーの一覧を閉じる。
    case closeCalendarFilter
    /// パネルを閉じる。
    case closePanel

    /// 詳細が開いていれば詳細、表示するカレンダーの一覧が開いていればそれ、どちらもなければパネルを閉じる。
    ///
    /// 月表示もコンパクト表示も同じ順序である。月表示では、詳細も一覧も、日の欄の中でスケジュールと入れ替わっている。
    public static func resolve(hasDetail: Bool, hasCalendarFilter: Bool = false) -> PopoverEscapeAction {
        if hasDetail { return .closeDetail }
        if hasCalendarFilter { return .closeCalendarFilter }
        return .closePanel
    }
}

/// アイコンの押下を、開く操作と閉じる操作のどちらにするかの判断。
///
/// アイコンを押すと、パネルが key でなくなって閉じたあとに、アイコンの操作が届くことがある。macOS 26 ではメニューバーの項目を
/// Control Center のプロセスが描くので、アイコンのマウスダウンが他のアプリのクリックとしてグローバルのモニターにも届き、
/// マウスアップでアイコンの操作が届く。そのまま開き直すと、閉じるつもりの押下が開き直しになる。
/// フォーカスの喪失か他のアプリのクリックで閉じた直後の押下は、閉じる操作として扱う。
public struct PopoverToggleGate: Equatable, Sendable {
    /// アイコンの押下で先に閉じたとみなす、押下までの間隔（秒）。マウスダウンからマウスアップまでの時間を含める。
    public static let focusLossWindow: TimeInterval = 0.5

    private var lastFocusLossClose: Date?

    public init() {}

    /// 閉じたことを記録する。アイコンの押下で先に起こりうる閉じ方（フォーカスの喪失、他のアプリのクリック）だけを覚える。
    public mutating func recordClose(_ reason: PopoverCloseReason, at now: Date) {
        if reason == .focusLoss || reason == .otherApp { lastFocusLossClose = now }
    }

    /// アイコンの押下で、パネルを開くか。表示中なら閉じる操作なので `false`。
    public func shouldOpen(isShown: Bool, at now: Date) -> Bool {
        if isShown { return false }
        guard let lastFocusLossClose else { return true }
        return now.timeIntervalSince(lastFocusLossClose) > Self.focusLossWindow
    }
}

extension CalendarPopoverViewModel {
    /// Esc を押したときの処理。詳細、表示するカレンダーの一覧の順に、開いていればそれを閉じる。何も閉じなかったとき（`.closePanel`）は、パネルを閉じるのは呼んだ側である。
    @discardableResult
    public func performEscape() -> PopoverEscapeAction {
        let action = PopoverEscapeAction.resolve(
            hasDetail: eventDetail != nil, hasCalendarFilter: isCalendarFilterOpen
        )
        switch action {
        case .closeDetail: closeDetail()
        case .closeCalendarFilter: closeCalendarFilter()
        case .closePanel: break
        }
        return action
    }
}
