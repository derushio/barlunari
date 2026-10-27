import Foundation

/// `NotificationCenter` の購読を、解放時に解除する入れ物。
///
/// ハンドラーには通知を送ったオブジェクトの識別子を渡す。`Notification` 自体は `Sendable` ではないため渡さない。
final class NotificationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(center: NotificationCenter, name: Notification.Name, handler: @escaping @Sendable (_ source: ObjectIdentifier?) -> Void) {
        self.center = center
        self.token = center.addObserver(forName: name, object: nil, queue: .main) { notification in handler(notification.object.map { ObjectIdentifier($0 as AnyObject) }) }
    }

    deinit {
        center.removeObserver(token)
    }
}
