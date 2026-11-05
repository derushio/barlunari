import BarlunariDomain

/// 出欠の回答で起きうる失敗。予定の内容は含まない。
public enum EventResponseError: Error, Equatable, Sendable {
    /// この予定には回答できない。出欠の概念がない予定、または自分が主催者の予定。
    case notRespondable
    /// 予定が見つからない。別の端末で削除されたか、繰り返しの予定が変更された。
    case eventNotFound
    /// この macOS では、アプリから出欠を書き込めない。
    case unsupported
    /// 保存に失敗した。カレンダーのアカウントが書き込みを許していない場合など。
    case saveFailed
}

/// 出欠の回答の保存が成功したときの結果。失敗は `EventResponseError` で投げる。
public enum EventResponseOutcome: Equatable, Sendable {
    /// 出欠を保存した。
    case saved
    /// 出欠は保存したが、保存のために外したこの回の通知（アラーム）を付け直せなかった。通知が消えたままになっている。
    case savedWithoutAlarms
}

/// 自分の出欠を変更して保存する。
public protocol EventResponder: Sendable {
    /// 表示している回だけの出欠を `response` にする。繰り返しの予定の他の回は変えない。
    /// - Returns: 出欠を保存できたときの結果。通知を付け直せなかったときは `.savedWithoutAlarms`。
    /// - Throws: `CalendarAccessError` か `EventResponseError`。
    func respond(to event: CalendarEvent.Identity, with response: AttendanceResponse) async throws -> EventResponseOutcome
}

/// 予定を標準のカレンダーアプリで開く。出欠の回答に失敗したときの逃げ道として使う。
public protocol CalendarAppOpener: Sendable {
    /// 開けたら `true`。予定が見つからない、開けるアプリがないなど、開けなかったら `false`。
    @discardableResult
    func open(_ event: CalendarEvent.Identity) async -> Bool
}
