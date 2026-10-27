import AppKit
import Foundation
import MenuDateApplication

/// `NSWorkspace` でシステム設定の画面を開く。アプリを前面には出さない。
@MainActor
public struct WorkspaceSystemSettingsOpener: SystemSettingsOpener {
    public init() {}

    public func open(_ destination: SystemSettingsDestination) -> Bool {
        NSWorkspace.shared.open(Self.url(for: destination))
    }

    static func url(for destination: SystemSettingsDestination) -> URL {
        switch destination {
        case .calendarPrivacy:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        case .internetAccounts:
            URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!
        }
    }
}
