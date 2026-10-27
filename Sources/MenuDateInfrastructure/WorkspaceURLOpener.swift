import AppKit
import Foundation
import MenuDateApplication

/// `NSWorkspace` で URL を開く。アプリを前面には出さず、既定のアプリに処理を渡す。
@MainActor
public struct WorkspaceURLOpener: URLOpener {
    public init() {}

    public func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
