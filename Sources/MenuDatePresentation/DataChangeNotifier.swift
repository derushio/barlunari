import Observation

/// 設定画面での変更（カレンダーの表示切り替え）と、許可の結果を、ポップオーバーと設定画面の間で伝える。
///
/// 値の中身には意味がなく、`revision` が変わったことだけが通知になる。
/// ViewModel 同士を直接参照させないための、Presentation 内の仲立ちである。
@MainActor
@Observable
public final class DataChangeNotifier {
    public private(set) var revision = 0

    public init() {}

    public func notifyChange() {
        revision += 1
    }
}
