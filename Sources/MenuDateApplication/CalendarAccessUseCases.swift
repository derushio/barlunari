/// カレンダーへのアクセスの許可を求める。利用者が許可のボタンを押したときだけ呼ぶ。
public struct RequestCalendarAccessUseCase: Sendable {
    private let authorizer: any CalendarAccessAuthorizer

    public init(authorizer: any CalendarAccessAuthorizer) {
        self.authorizer = authorizer
    }

    /// 結果の許可の状態を返す。
    @discardableResult
    public func execute() async throws -> CalendarAuthorizationStatus {
        try await authorizer.requestAccess()
    }
}

/// システム設定の画面を開く。
@MainActor
public struct OpenSystemSettingsUseCase: Sendable {
    private let opener: any SystemSettingsOpener

    public init(opener: any SystemSettingsOpener) {
        self.opener = opener
    }

    @discardableResult
    public func execute(_ destination: SystemSettingsDestination) -> Bool {
        opener.open(destination)
    }
}
