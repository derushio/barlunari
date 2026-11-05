import BarlunariApplication

/// エラーを利用者に見せる日本語の文にする。内部の詳細は文に含めない。
enum UserFacingMessage {
    static func text(for error: any Error) -> String {
        switch error {
        case let error as CalendarAccessError: CalendarAccessGuide(error).message
        case let error as EventResponseError: text(for: error)
        default: "予期しないエラーが発生しました。もう一度お試しください。"
        }
    }

    /// 出欠の回答の失敗。利用者が次にとれる行動まで書く。
    static func text(for error: EventResponseError) -> String {
        switch error {
        case .notRespondable: "この予定には回答できません。"
        case .eventNotFound: "予定が見つかりませんでした。カレンダーで予定を開いて確認してください。"
        case .unsupported: "この macOS では、このアプリから出欠を回答できません。カレンダーで回答してください。"
        case .saveFailed: "回答を保存できませんでした。このカレンダーのアカウントが、出欠の変更を許可していない可能性があります。カレンダーで回答してください。"
        }
    }
}
