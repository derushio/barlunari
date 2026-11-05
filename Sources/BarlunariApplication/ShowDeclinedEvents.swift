/// 「辞退した予定を表示」の既定値。保存がないときは、辞退した予定を表示する。
public enum ShowDeclinedEventsDefault {
    public static let value = true
}

/// 「辞退した予定を表示」の保存先。ポップオーバーを開いたときの最初の描画から保存した値で絞り込めるよう、同期の API にする。
public protocol ShowDeclinedEventsStore: Sendable {
    /// 保存した値。保存がなければ `nil`。
    func load() -> Bool?
    func save(_ show: Bool)
}
