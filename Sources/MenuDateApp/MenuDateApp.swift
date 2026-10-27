import AppKit

/// `@main`。SwiftUI の `App` のシーンは使わず、`NSApplication` と `AppDelegate` で起動する。
@main
enum MenuDateMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // Info.plist の LSUIElement と同じく、Dock とアプリ切り替えに出さない。
        application.setActivationPolicy(.accessory)
        // delegate は NSApplication が弱参照で持つので、run() が戻るまで保持する。
        withExtendedLifetime(delegate) { application.run() }
    }
}
