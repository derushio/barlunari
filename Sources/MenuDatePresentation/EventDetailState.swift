import Foundation
import MenuDateDomain

/// 予定の詳細の表示内容。値がない項目は `nil` か空で、View は出さない。
public struct EventDetailState: Equatable, Sendable {
    public let id: CalendarEvent.Identity
    public let color: CalendarColor?
    public let title: String
    /// `10月24日(土) 14:00〜15:30`。
    public let dateText: String
    public let calendarName: String?
    public let accountName: String?
    public let location: String?
    public let meetingURL: URL?
    public let detailURL: URL?
    /// 自分の出欠。出欠の概念がない予定では `nil`。
    public let attendanceText: String?
    public let participants: [ParticipantRowState]
    /// http と https の URL をリンクにしたメモ。
    public let notes: AttributedString?

    /// カレンダー名とアカウント名を 1 行にした文。同じ名前なら 1 つだけ出す。
    public var calendarText: String? {
        switch (calendarName, accountName) {
        case let (calendar?, account?): calendar == account ? calendar : "\(calendar)（\(account)）"
        case let (calendar?, nil): calendar
        case let (nil, account?): account
        case (nil, nil): nil
        }
    }
}

/// 予定の詳細に出す参加者 1 人分の表示内容。
public struct ParticipantRowState: Identifiable, Equatable, Sendable {
    public let id: Int
    /// 名前、なければメールアドレス。
    public let displayName: String
    /// 名前があるときだけ持つ。名前がなければ `displayName` がメールアドレスである。
    public let emailAddress: String?
    public let isOrganizer: Bool
    public let isCurrentUser: Bool
    public let attendance: AttendanceStatus
    /// 出欠の概念がない参加者は `nil`。
    public let attendanceText: String?

    /// VoiceOver に読ませる文。
    public var accessibilityLabel: String {
        [displayName, isOrganizer ? "主催者" : nil, isCurrentUser ? "自分" : nil, attendanceText]
            .compactMap { $0 }
            .joined(separator: "、")
    }
}

extension AttendanceStatus {
    /// 出欠の表示文。`notApplicable` は出さないため `nil`。
    var displayText: String? {
        switch self {
        case .accepted: "承諾"
        case .tentative: "未定"
        case .needsAction: "未回答"
        case .declined: "辞退"
        case .notApplicable: nil
        }
    }
}
