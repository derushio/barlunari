/// 利用者が招待に返す出欠の回答。承諾・未定・辞退の 3 値で、未回答には戻せない。
public enum AttendanceResponse: Sendable, Hashable, CaseIterable {
    case accepted
    case tentative
    case declined

    /// この回答をしたあとの自分の出欠。
    public var attendance: AttendanceStatus {
        switch self {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        }
    }
}
