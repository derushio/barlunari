import Foundation

/// URL を既定のアプリで開く。予定の詳細と会議の URL を開くのに使う。
@MainActor
public protocol URLOpener: Sendable {
    /// 開けたら `true`。開けるアプリがないなど、開けなかったら `false`。
    @discardableResult
    func open(_ url: URL) -> Bool
}
