import BarlunariDomain

/// 予定の一覧（予定一覧、日の欄、月のマス目）で示す出欠。
///
/// 承諾・未定・出欠のない予定は、承諾した予定と同じ見た目なので `none` にする。
public enum ListedAttendance: Equatable, Sendable {
    case none
    /// まだ回答していない招待。回答できない予定（自分が主催者など）は含めない。
    case needsResponse
    case declined

    init(_ event: CalendarEvent) {
        switch event.attendance {
        case .needsAction where event.canRespond: self = .needsResponse
        case .declined: self = .declined
        default: self = .none
        }
    }

    /// 余白のある場所に出す文字と VoiceOver で読む文字。`none` は `nil`。
    public var label: String? {
        switch self {
        case .none: nil
        case .needsResponse: "未回答"
        case .declined: "辞退"
        }
    }
}
