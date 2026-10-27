/// 自分の出欠。`notApplicable` は出欠の概念がない予定（自分だけの予定など）を表す。
public enum AttendanceStatus: String, Sendable, Hashable, CaseIterable {
    case accepted
    case tentative
    case declined
    case needsAction
    case notApplicable
}
