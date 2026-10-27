import Foundation

// EventKit の `EKSource`、`EKCalendar`、`EKEvent` から写した、EventKit に依存しない値。
// EventKit の型は `Sendable` ではないため、`EventKitCalendarStore` の外へはこの値だけを出す。
// ドメインの型への変換は `EventKitMapper` が行う。

struct EventKitSourceValue: Sendable, Equatable {
    let sourceIdentifier: String
    let title: String
}

/// sRGB の各成分。0 から 1 の範囲。
struct EventKitColorValue: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
}

struct EventKitCalendarValue: Sendable, Equatable {
    let calendarIdentifier: String
    let title: String
    let sourceIdentifier: String
    /// 色を取れなかったカレンダーは `nil`。
    let color: EventKitColorValue?
}

/// 自分の出欠。`EKParticipantStatus` に対応する。
enum EventKitParticipantStatus: Sendable, Equatable {
    case unknown, pending, accepted, declined, tentative, delegated, completed, inProcess
}

/// `EKParticipant` から写した値。
struct EventKitParticipantValue: Sendable, Equatable {
    let name: String?
    /// `mailto:` のときだけメールアドレスになる。CalDAV のカレンダーでは、それ以外の URL が入ることがある。
    let url: URL?
    let status: EventKitParticipantStatus
    let isCurrentUser: Bool
}

struct EventKitEventValue: Sendable, Equatable {
    /// 保存されていない予定は `nil`。
    let eventIdentifier: String?
    let calendarItemIdentifier: String
    /// CalDAV のカレンダーでは iCalendar の UID である。
    let calendarItemExternalIdentifier: String?
    let calendarIdentifier: String
    let sourceIdentifier: String
    let title: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: URL?
    /// `isCurrentUser` の参加者の状態。参加者がいない予定と、自分が参加者にいない予定は `nil`。
    let currentUserStatus: EventKitParticipantStatus?
    /// 主催者。持たない予定は `nil`。
    let organizer: EventKitParticipantValue?
    let attendees: [EventKitParticipantValue]
}
