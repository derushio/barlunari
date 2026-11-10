import SwiftUI

/// メニューバーの項目を、スナップショットで確かめるための View。実際の項目は `MenuBarController` が `NSStatusItem` で出す。
///
/// `countdownText` があれば、アイコンの代わりに等幅数字で残り時間を出す。なければアイコンを出す。
public struct MenuBarLabelView: View {
    private let countdownText: String?

    public init(countdownText: String? = nil) {
        self.countdownText = countdownText
    }

    public var body: some View {
        if let countdownText {
            Text(countdownText)
                .font(Font(NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)))
                .accessibilityLabel("次の予定まで\(countdownText)")
        } else {
            Image(systemName: MenuBarIcon.symbolName)
                .accessibilityLabel(MenuBarIcon.accessibilityLabel)
        }
    }
}
