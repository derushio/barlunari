import MenuDateApplication

/// エラーを利用者に見せる日本語の文にする。内部の詳細は文に含めない。
enum UserFacingMessage {
    static func text(for error: any Error) -> String {
        switch error {
        case let error as CalendarAccessError: CalendarAccessGuide(error).message
        default: "予期しないエラーが発生しました。もう一度お試しください。"
        }
    }
}
