import Foundation
import MenuDateApplication
import MenuDateDomain

/// EventKit から写した値を、ドメインの型に変換する腐敗防止層。EventKit の型には依存しない。
///
/// 日付の計算には `DateProvider` の暦を使う。暦は呼ぶたびに読み、タイムゾーンの変更に追従する。
struct EventKitMapper: Sendable {
    /// 色を取れないカレンダーに使う灰色。
    static let fallbackColor = CalendarColor(red: 0x80, green: 0x80, blue: 0x80)

    private let dateProvider: any DateProvider

    init(dateProvider: any DateProvider) {
        self.dateProvider = dateProvider
    }

    // MARK: - アカウントとカレンダー

    func account(from source: EventKitSourceValue) throws -> UserAccount {
        try UserAccount(id: AccountID(source.sourceIdentifier), name: source.title)
    }

    func calendar(from value: EventKitCalendarValue) throws -> UserCalendar {
        UserCalendar(
            accountID: try AccountID(value.sourceIdentifier),
            id: try CalendarID(value.calendarIdentifier),
            name: value.title,
            color: value.color.map(Self.color(from:)) ?? Self.fallbackColor
        )
    }

    static func color(from value: EventKitColorValue) -> CalendarColor {
        func byte(_ component: Double) -> UInt8 {
            UInt8((min(max(component, 0), 1) * 255).rounded())
        }
        return CalendarColor(red: byte(value.red), green: byte(value.green), blue: byte(value.blue))
    }

    // MARK: - 予定

    func event(from value: EventKitEventValue) throws -> CalendarEvent {
        let calendar = dateProvider.calendar
        let meetingURL = Self.meetingURL(url: value.url, location: value.location, notes: value.notes)
        return CalendarEvent(
            accountID: try AccountID(value.sourceIdentifier),
            id: try Self.eventID(of: value),
            calendarID: try CalendarID(value.calendarIdentifier),
            title: value.title ?? "",
            schedule: try Self.schedule(of: value, calendar: calendar),
            location: Self.trimmedNonEmpty(value.location),
            meetingURL: meetingURL,
            detailURL: Self.detailURL(of: value.url, meetingURL: meetingURL),
            notes: Self.cleanedNotes(value.notes),
            participants: Self.participants(of: value),
            attendance: Self.attendance(of: value.currentUserStatus),
            iCalendarUID: value.calendarItemExternalIdentifier
        )
    }

    /// 繰り返しの予定はすべての回が同じ `eventIdentifier` を持つため、回の開始日時と組にして回を区別する。
    static func eventID(of value: EventKitEventValue) throws -> EventID {
        let identifier = value.eventIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? value.calendarItemIdentifier
        let start = Int64(value.startDate.timeIntervalSince1970.rounded())
        return try EventID("\(identifier)@\(start)")
    }

    /// 終日予定の終了日は排他的である。
    ///
    /// EventKit の終日予定の `endDate` は、最終日の終わり（23:59:59）のことと、翌日の 0:00 のことがある。
    /// 開始より後の 0:00 ちょうどならその日を終了日にし、それ以外は `endDate` の日の翌日を終了日にする。
    static func schedule(of value: EventKitEventValue, calendar: Calendar) throws -> EventSchedule {
        guard value.isAllDay else {
            // 終了が開始より前の予定は、長さ 0 として扱う。`DateInterval` は終了が開始より前だと異常終了する。
            return .timed(DateInterval(start: value.startDate, end: max(value.startDate, value.endDate)))
        }
        let startDay = CalendarDay(date: value.startDate, calendar: calendar)
        let endDay = CalendarDay(date: value.endDate, calendar: calendar)
        let endsAtMidnight = value.endDate == endDay.startDate(in: calendar) && value.endDate > value.startDate
        let exclusiveEnd = endsAtMidnight ? endDay : endDay.adding(days: 1, calendar: calendar)
        // 終了が開始より前の予定でも、少なくとも 1 日にする。
        let minimumEnd = startDay.adding(days: 1, calendar: calendar)
        return .allDay(try DayRange(start: startDay, end: max(exclusiveEnd, minimumEnd)))
    }

    static func attendance(of status: EventKitParticipantStatus?) -> AttendanceStatus {
        switch status {
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        case .pending, .unknown: .needsAction
        case .delegated, .completed, .inProcess, nil: .notApplicable
        }
    }

    // MARK: - メモと参加者

    /// Google が会議の情報として付けるブロックを取り除いたメモ。
    ///
    /// ブロックは `-::~` で始まり `::-` で終わる区切り線の行で囲まれる。会議の URL の判定には使わない。
    /// 対になる区切り線がなければ、メモの本文を失わないよう取り除かない。
    static func cleanedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let lines = notes.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var kept: [String] = []
        var index = 0
        while index < lines.count {
            if isGoogleDelimiter(lines[index]),
               let close = lines[(index + 1)...].firstIndex(where: isGoogleDelimiter) {
                index = close + 1
                continue
            }
            kept.append(lines[index])
            index += 1
        }

        // 空行が 3 行以上続いたら、1 行にまとめる。空白だけの行も空行とみなす。
        var collapsed: [String] = []
        var blankRun: [String] = []
        func flushBlankRun() {
            if blankRun.count >= 3 { collapsed.append("") } else { collapsed.append(contentsOf: blankRun) }
            blankRun.removeAll()
        }
        for line in kept {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun.append(line)
            } else {
                flushBlankRun()
                collapsed.append(line)
            }
        }
        flushBlankRun()

        return trimmedNonEmpty(collapsed.joined(separator: "\n"))
    }

    private static func isGoogleDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("-::~") && trimmed.hasSuffix("::-")
    }

    /// 主催者を先頭に置き、続けて参加者を並べる。主催者が参加者にもいれば 1 人にまとめる。
    ///
    /// 名前もメールアドレスもない参加者は、予定の変換を失敗させずに除く。
    static func participants(of value: EventKitEventValue) -> [EventParticipant] {
        guard let organizer = value.organizer else {
            return value.attendees.compactMap { participant(from: $0, isOrganizer: false) }
        }
        // 参加者の側にいる主催者は、参加者の側の出欠を使う。主催者の側に名前やメールアドレスがなければ補う。
        let matching = value.attendees.first { isSame(organizer, $0) }
        let merged = EventKitParticipantValue(
            name: trimmedNonEmpty(organizer.name) ?? matching?.name,
            url: emailAddress(of: organizer.url) != nil ? organizer.url : (matching?.url ?? organizer.url),
            status: matching?.status ?? organizer.status,
            isCurrentUser: organizer.isCurrentUser || (matching?.isCurrentUser ?? false)
        )
        let others = value.attendees.filter { !isSame(organizer, $0) }
        return ([participant(from: merged, isOrganizer: true)] + others.map { participant(from: $0, isOrganizer: false) })
            .compactMap { $0 }
    }

    private static func participant(from value: EventKitParticipantValue, isOrganizer: Bool) -> EventParticipant? {
        try? EventParticipant(
            name: value.name,
            emailAddress: emailAddress(of: value.url),
            attendance: attendance(of: value.status),
            isOrganizer: isOrganizer,
            isCurrentUser: value.isCurrentUser
        )
    }

    /// `mailto:` の URL からメールアドレスを取り出す。それ以外の URL は無視する。
    static func emailAddress(of url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "mailto",
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
        else { return nil }
        return trimmedNonEmpty(path)
    }

    /// メールアドレスが大文字小文字を除いて同じか、メールアドレスがなければ名前が同じなら、同じ参加者とみなす。
    private static func isSame(_ lhs: EventKitParticipantValue, _ rhs: EventKitParticipantValue) -> Bool {
        if let left = emailAddress(of: lhs.url), let right = emailAddress(of: rhs.url) {
            return left.lowercased() == right.lowercased()
        }
        guard emailAddress(of: lhs.url) == nil, emailAddress(of: rhs.url) == nil,
              let left = trimmedNonEmpty(lhs.name), let right = trimmedNonEmpty(rhs.name)
        else { return false }
        return left == right
    }

    // MARK: - URL

    /// 予定の URL、場所、メモの順に探し、最初に見つかった会議サービスの URL を返す。
    ///
    /// Google Meet、Zoom、Teams のリンクは予定の URL に入らず、メモに入っていることがある。
    static func meetingURL(url: URL?, location: String?, notes: String?) -> URL? {
        var candidates: [URL] = []
        if let url { candidates.append(url) }
        for text in [location, notes] {
            if let text { candidates.append(contentsOf: urls(in: text)) }
        }
        return candidates.first(where: isMeetingURL)
    }

    /// 予定の URL が http か https で、会議の URL と違うときだけ詳細の URL にする。
    static func detailURL(of url: URL?, meetingURL: URL?) -> URL? {
        guard let url, isWebURL(url), url != meetingURL else { return nil }
        return url
    }

    static func isMeetingURL(_ url: URL) -> Bool {
        guard isWebURL(url), let host = url.host?.lowercased() else { return false }
        return host == "meet.google.com"
            || host == "zoom.us" || host.hasSuffix(".zoom.us")
            || host == "teams.microsoft.com"
            || host == "teams.live.com"
            || host.hasSuffix(".webex.com")
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// 文中の http と https の URL を、現れた順に返す。末尾の句読点は URL に含めない。
    static func urls(in text: String) -> [URL] {
        let pattern = /https?:\/\/[^\s<>"'\)\]]+/
        return text.matches(of: pattern).compactMap { match in
            var candidate = String(match.output)
            while let last = candidate.last, ".,;:!?".contains(last) { candidate.removeLast() }
            return URL(string: candidate)
        }
    }

    private static func trimmedNonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
