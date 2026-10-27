/// メニューバーの項目に出すアイコンの仕様。日付は macOS の時計が表示するため、アイコンだけを出す。
public enum MenuBarIcon {
    public static let symbolName = "calendar"
    /// アイコンだけでは VoiceOver が読めないため、アプリ名を読ませる。
    public static let accessibilityLabel = "MenuDate"
}
