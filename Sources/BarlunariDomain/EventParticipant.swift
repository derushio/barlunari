import Foundation

/// 予定の参加者。名前とメールアドレスのどちらかは必ず持つ。
public struct EventParticipant: Sendable, Hashable {
    public let name: String?
    public let emailAddress: String?
    public let attendance: AttendanceStatus
    public let isOrganizer: Bool
    public let isCurrentUser: Bool

    /// 名前とメールアドレスの前後の空白は取り除き、空なら `nil` にする。
    /// - Throws: 名前もメールアドレスもなければ `DomainError.participantWithoutNameOrEmail`。
    public init(
        name: String?,
        emailAddress: String?,
        attendance: AttendanceStatus = .notApplicable,
        isOrganizer: Bool = false,
        isCurrentUser: Bool = false
    ) throws {
        let name = Self.normalized(name)
        let emailAddress = Self.normalized(emailAddress)
        guard name != nil || emailAddress != nil else { throw DomainError.participantWithoutNameOrEmail }
        self.name = name
        self.emailAddress = emailAddress
        self.attendance = attendance
        self.isOrganizer = isOrganizer
        self.isCurrentUser = isCurrentUser
    }

    private init(copying other: EventParticipant, attendance: AttendanceStatus) {
        name = other.name
        emailAddress = other.emailAddress
        self.attendance = attendance
        isOrganizer = other.isOrganizer
        isCurrentUser = other.isCurrentUser
    }

    /// 出欠だけを変えた参加者。名前とメールアドレスは検証済みの値を引き継ぐ。
    public func with(attendance: AttendanceStatus) -> EventParticipant {
        EventParticipant(copying: self, attendance: attendance)
    }

    /// 名前、なければメールアドレス。
    public var displayName: String {
        // 不変条件により、どちらかは必ず持つ。
        name ?? emailAddress ?? ""
    }

    private static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
