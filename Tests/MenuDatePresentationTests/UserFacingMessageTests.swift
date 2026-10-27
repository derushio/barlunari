import MenuDateApplication
import Testing

@testable import MenuDatePresentation

@Suite struct UserFacingMessageTests {
    @Test(arguments: [
        (CalendarAccessError.notDetermined, CalendarAccessGuide.notDetermined),
        (.denied, .denied),
        (.noCalendars, .noCalendars),
    ])
    func カレンダー取得のエラーを案内に対応させる(error: CalendarAccessError, guide: CalendarAccessGuide) {
        #expect(CalendarAccessGuide(error) == guide)
        #expect(UserFacingMessage.text(for: error) == guide.message)
    }

    @Test(arguments: [
        (CalendarAccessGuide.notDetermined, "カレンダーへのアクセスを許可"),
        (.denied, "システム設定を開く"),
        (.noCalendars, "「インターネットアカウント」を開く"),
    ])
    func 案内のボタンの文言(guide: CalendarAccessGuide, title: String) {
        #expect(guide.buttonTitle == title)
    }

    @Test func 未知のエラーは内部の詳細を出さない() {
        struct Secret: Error {}
        #expect(UserFacingMessage.text(for: Secret()) == "予期しないエラーが発生しました。もう一度お試しください。")
    }
}
