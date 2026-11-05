import BarlunariDomain

/// 予定の出欠を回答する。
public struct RespondToEventUseCase: Sendable {
    private let responder: any EventResponder

    public init(responder: any EventResponder) {
        self.responder = responder
    }

    /// 回答できない予定では、`EventResponseError.notRespondable` を投げ、何も書き込まない。
    /// - Returns: 保存の結果。通知を付け直せなかったときは `.savedWithoutAlarms`。
    public func execute(event: CalendarEvent, response: AttendanceResponse) async throws -> EventResponseOutcome {
        guard event.canRespond else { throw EventResponseError.notRespondable }
        return try await responder.respond(to: event.id, with: response)
    }
}

/// 予定を標準のカレンダーアプリで開く。
public struct OpenEventInCalendarAppUseCase: Sendable {
    private let opener: any CalendarAppOpener

    public init(opener: any CalendarAppOpener) {
        self.opener = opener
    }

    @discardableResult
    public func execute(_ event: CalendarEvent.Identity) async -> Bool {
        await opener.open(event)
    }
}
