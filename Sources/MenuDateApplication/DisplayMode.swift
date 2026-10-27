/// ポップオーバーの表示モード。
public enum CalendarDisplayMode: String, Sendable, CaseIterable {
    /// 予定を月のマス目の中に並べる、大きな 1 枚のカレンダー。
    case month
    /// 小さな月のマス目と、日ごとの予定一覧。
    case compact

    /// 保存がないときのモード。
    public static let `default`: CalendarDisplayMode = .month
}

/// 表示モードの保存先。起動直後の最初の描画から保存したモードで出し、既定のモードから切り替わるちらつきを出さないため、同期の API にする。
public protocol DisplayModeStore: Sendable {
    /// 保存したモード。保存がないか、読めない値なら `nil`。
    func load() -> CalendarDisplayMode?
    func save(_ mode: CalendarDisplayMode)
}
