import Foundation
import BarlunariDomain

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
    /// メニューバーの残り時間に含めるか。利用者が選んだ値、なければ既定の値（時刻付きは含める、終日は含めない）。参加状況に左右されない。
    public let includedInCountdown: Bool
    /// 自分が辞退した予定か。辞退した予定は、チェックボックスがオンでも残り時間に数えないので、View が説明を出す。
    public let isDeclined: Bool
    /// 出欠を回答できる予定の回答欄。回答できない予定は `nil` で、View は `attendanceText` の行を出す。
    public let rsvp: EventRSVPState?
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

/// 予定の詳細の出欠の回答欄の表示内容。
public struct EventRSVPState: Equatable, Sendable {
    /// 自分の現在の出欠。ボタンの選択状態になる。
    public let current: AttendanceStatus
    /// 保存中の回答。`nil` でなければ、ボタンを無効にする。
    public let responding: AttendanceResponse?
    /// 回答に失敗した理由か、通知を付け直せなかった案内。`nil` でなければ、「カレンダーで開く」ボタンを出す。
    public let errorMessage: String?

    public var isResponding: Bool { responding != nil }
}

extension AttendanceResponse {
    var title: String {
        switch self {
        case .accepted: "承諾"
        case .tentative: "未定"
        case .declined: "辞退"
        }
    }

    /// 選んでいないときは輪郭、選んでいるときは塗りの記号にして、色が見えなくても区別できるようにする。
    func symbol(isSelected: Bool) -> String {
        switch self {
        case .accepted: isSelected ? "checkmark.circle.fill" : "checkmark.circle"
        case .tentative: isSelected ? "questionmark.circle.fill" : "questionmark.circle"
        case .declined: isSelected ? "xmark.circle.fill" : "xmark.circle"
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
