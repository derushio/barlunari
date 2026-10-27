import SwiftUI

/// メニューバーの項目のアイコンを、スナップショットで確かめるための View。実際の項目は `MenuBarController` が `NSStatusItem` で出す。
public struct MenuBarLabelView: View {
    public init() {}

    public var body: some View {
        Image(systemName: MenuBarIcon.symbolName)
            .accessibilityLabel(MenuBarIcon.accessibilityLabel)
    }
}
