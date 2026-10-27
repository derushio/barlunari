import Foundation

extension Notification.Name {
    /// OS のカレンダーのデータが変わったときに、Infrastructure が `NotificationCenter.default` に送る通知。
    ///
    /// 同期による予定の追加や、アカウントの追加と削除で送られる。購読した側は予定とカレンダーを読み直す。
    public static let calendarStoreDidChange = Notification.Name("io.github.derushio.Barlunari.calendarStoreDidChange")
}
