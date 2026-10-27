import OSLog

/// ログの出力先。予定のタイトル・場所・メモ・URL など、予定の内容はどのカテゴリにも出さない。
enum Log {
    static let subsystem = AppIdentity.bundleIdentifier

    static let calendar = Logger(subsystem: subsystem, category: "calendar")
}
