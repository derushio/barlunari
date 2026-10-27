import Foundation

/// 一定の間隔でメインアクターの処理を繰り返す。解放時に止まる。
///
/// 間隔には `tolerance` を付け、OS がほかのタイマーとまとめて起こせるようにする。
final class RepeatingTask: Sendable {
    private let task: Task<Void, Never>

    init(interval: Duration, tolerance: Duration, action: @escaping @MainActor @Sendable () -> Void) {
        task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval, tolerance: tolerance)
                } catch {
                    return
                }
                await action()
            }
        }
    }

    deinit {
        task.cancel()
    }
}
