import Foundation
import MenuDateApplication
import MenuDateDomain
import MenuDatePreviewSupport
import Testing
@testable import MenuDateInfrastructure

@Suite struct EventKitMapperTests {
    let mapper = EventKitMapper(dateProvider: FixedDateProvider())
    let calendar = SampleData.calendar

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    func value(
        eventIdentifier: String? = "event-1",
        calendarItemIdentifier: String = "item-1",
        uid: String? = "uid-1@example.com",
        title: String? = "会議",
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
        status: EventKitParticipantStatus? = nil,
        organizer: EventKitParticipantValue? = nil,
        attendees: [EventKitParticipantValue] = []
    ) -> EventKitEventValue {
        EventKitEventValue(
            eventIdentifier: eventIdentifier,
            calendarItemIdentifier: calendarItemIdentifier,
            calendarItemExternalIdentifier: uid,
            calendarIdentifier: "calendar-1",
            sourceIdentifier: "source-1",
            title: title,
            startDate: start ?? date(2026, 10, 24, 10),
            endDate: end ?? date(2026, 10, 24, 11),
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            url: url,
            currentUserStatus: status,
            organizer: organizer,
            attendees: attendees
        )
    }

    // MARK: - アカウントとカレンダー

    @Test func sourceをアカウントに変換する() throws {
        let account = try mapper.account(from: EventKitSourceValue(sourceIdentifier: "source-1", title: " Google "))
        #expect(account.id.rawValue == "source-1")
        #expect(account.name == "Google")
    }

    @Test func 名前が空のsourceはアカウントにできない() {
        #expect(throws: DomainError.emptyAccountName) {
            try mapper.account(from: EventKitSourceValue(sourceIdentifier: "source-1", title: " "))
        }
    }

    @Test func カレンダーを変換して色をsRGBの16進にする() throws {
        let calendar = try mapper.calendar(from: EventKitCalendarValue(
            calendarIdentifier: "calendar-1", title: "仕事", sourceIdentifier: "source-1",
            color: EventKitColorValue(red: 1, green: 0.5, blue: 0)
        ))
        #expect(calendar.id.accountID.rawValue == "source-1")
        #expect(calendar.id.calendarID.rawValue == "calendar-1")
        #expect(calendar.name == "仕事")
        #expect(calendar.color.hexString == "#FF8000")
    }

    @Test func 色を取れないカレンダーは灰色にする() throws {
        let calendar = try mapper.calendar(from: EventKitCalendarValue(
            calendarIdentifier: "calendar-1", title: "仕事", sourceIdentifier: "source-1", color: nil
        ))
        #expect(calendar.color == EventKitMapper.fallbackColor)
    }

    @Test(arguments: [(-0.2, UInt8(0)), (0, 0), (0.5, 128), (1, 255), (1.4, 255)])
    func 色の成分は0から255に収める(component: Double, expected: UInt8) {
        let color = EventKitMapper.color(from: EventKitColorValue(red: component, green: 0, blue: 0))
        #expect(color.red == expected)
    }

    // MARK: - 予定の同一性

    @Test func 予定IDはeventIdentifierと回の開始日時から作る() throws {
        let first = try EventKitMapper.eventID(of: value(start: date(2026, 10, 24, 10)))
        let second = try EventKitMapper.eventID(of: value(start: date(2026, 10, 31, 10)))
        #expect(first != second)
        #expect(first.rawValue.hasPrefix("event-1@"))
    }

    @Test func eventIdentifierがなければcalendarItemIdentifierを使う() throws {
        #expect(try EventKitMapper.eventID(of: value(eventIdentifier: nil)).rawValue.hasPrefix("item-1@"))
        #expect(try EventKitMapper.eventID(of: value(eventIdentifier: "")).rawValue.hasPrefix("item-1@"))
    }

    @Test func UIDを持つ予定は共有キーを持ち持たない予定は持たない() throws {
        #expect(try mapper.event(from: value(uid: "uid-1")).iCalendarUID == "uid-1")
        #expect(try mapper.event(from: value(uid: nil)).sharedKey == nil)
        #expect(try mapper.event(from: value(uid: "")).sharedKey == nil)
    }

    @Test func 別のアカウントの同じUIDと日時の予定は同じ共有キーになる() throws {
        let a = try mapper.event(from: value(uid: "holiday"))
        let b = try mapper.event(from: EventKitEventValue(
            eventIdentifier: "other", calendarItemIdentifier: "other-item", calendarItemExternalIdentifier: "holiday",
            calendarIdentifier: "calendar-2", sourceIdentifier: "source-2", title: "会議",
            startDate: date(2026, 10, 24, 10), endDate: date(2026, 10, 24, 11), isAllDay: false,
            location: nil, notes: nil, url: nil, currentUserStatus: nil, organizer: nil, attendees: []
        ))
        #expect(a.id != b.id)
        #expect(a.sharedKey == b.sharedKey)
    }

    // MARK: - 日時

    @Test func 時刻付きの予定は開始と終了の間隔にする() throws {
        let event = try mapper.event(from: value())
        #expect(event.schedule == .timed(DateInterval(start: date(2026, 10, 24, 10), end: date(2026, 10, 24, 11))))
    }

    @Test func 終了が開始より前の時刻付きの予定は長さ0にする() throws {
        let event = try mapper.event(from: value(start: date(2026, 10, 24, 10), end: date(2026, 10, 24, 9)))
        #expect(event.schedule == .timed(DateInterval(start: date(2026, 10, 24, 10), end: date(2026, 10, 24, 10))))
    }

    @Test func 終日予定の終了が最終日の終わりならその翌日を終了日にする() throws {
        let event = try mapper.event(from: value(
            start: date(2026, 10, 25), end: date(2026, 10, 25, 23, 59, 59), isAllDay: true
        ))
        #expect(event.schedule == .allDay(try DayRange(start: SampleData.day(2026, 10, 25), end: SampleData.day(2026, 10, 26))))
    }

    @Test func 複数日の終日予定の終了が翌日の0時ちょうどならその日を終了日にする() throws {
        let event = try mapper.event(from: value(start: date(2026, 10, 27), end: date(2026, 10, 30), isAllDay: true))
        #expect(event.schedule == .allDay(try DayRange(start: SampleData.day(2026, 10, 27), end: SampleData.day(2026, 10, 30))))
    }

    @Test func 複数日の終日予定の終了が最終日の終わりなら最終日を含める() throws {
        let event = try mapper.event(from: value(
            start: date(2026, 10, 27), end: date(2026, 10, 29, 23, 59, 59), isAllDay: true
        ))
        #expect(event.schedule == .allDay(try DayRange(start: SampleData.day(2026, 10, 27), end: SampleData.day(2026, 10, 30))))
    }

    @Test func 終日予定の終了が開始と同じ0時なら1日にする() throws {
        let event = try mapper.event(from: value(start: date(2026, 10, 25), end: date(2026, 10, 25), isAllDay: true))
        #expect(event.schedule == .allDay(try DayRange(start: SampleData.day(2026, 10, 25), end: SampleData.day(2026, 10, 26))))
    }

    @Test func 終了が開始より前の終日予定でも1日にする() throws {
        let event = try mapper.event(from: value(start: date(2026, 10, 25), end: date(2026, 10, 20), isAllDay: true))
        #expect(event.schedule == .allDay(try DayRange(start: SampleData.day(2026, 10, 25), end: SampleData.day(2026, 10, 26))))
    }

    @Test func 日付の計算にはDateProviderの暦を使う() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let utcMapper = EventKitMapper(dateProvider: FixedDateProvider(calendar: utc))
        // 東京の 10/25 0:00 は UTC では 10/24 15:00 である。
        let event = try utcMapper.event(from: value(
            start: date(2026, 10, 25), end: date(2026, 10, 25, 23, 59, 59), isAllDay: true
        ))
        #expect(event.schedule == .allDay(try DayRange(start: SampleData.day(2026, 10, 24), end: SampleData.day(2026, 10, 26))))
    }

    // MARK: - 出欠

    @Test(arguments: [
        (EventKitParticipantStatus.accepted, AttendanceStatus.accepted),
        (.declined, .declined),
        (.tentative, .tentative),
        (.pending, .needsAction),
        (.unknown, .needsAction),
        (.delegated, .notApplicable),
        (.completed, .notApplicable),
        (.inProcess, .notApplicable),
    ])
    func 自分の参加状態を出欠に写す(status: EventKitParticipantStatus, expected: AttendanceStatus) {
        #expect(EventKitMapper.attendance(of: status) == expected)
    }

    @Test func 参加者がいなければ出欠の概念がない() throws {
        #expect(try mapper.event(from: value(status: nil)).attendance == .notApplicable)
    }

    // MARK: - 会議の URL

    @Test(arguments: [
        "https://meet.google.com/abc-defg-hij",
        "https://zoom.us/j/123456789",
        "https://us02web.zoom.us/j/123456789?pwd=abc",
        "https://teams.microsoft.com/l/meetup-join/xyz",
        "https://teams.live.com/meet/123",
        "https://example.webex.com/meet/room",
    ])
    func 会議サービスのURLを会議のURLと判定する(text: String) {
        #expect(EventKitMapper.isMeetingURL(URL(string: text)!))
    }

    @Test(arguments: [
        "https://example.com/zoom.us",
        "https://notzoom.us/j/1",
        "https://meet.google.com.evil.example/x",
        "https://webex.com/meet/room",
        "ftp://meet.google.com/abc",
        "mailto:a@zoom.us",
    ])
    func 会議サービスでないURLは会議のURLと判定しない(text: String) {
        #expect(!EventKitMapper.isMeetingURL(URL(string: text)!))
    }

    @Test func 会議のURLはメモから探す() throws {
        let notes = """
        打ち合わせです。
        Google Meet で参加: https://meet.google.com/abc-defg-hij?hs=224
        資料: https://example.com/doc
        """
        let event = try mapper.event(from: value(notes: notes))
        #expect(event.meetingURL == URL(string: "https://meet.google.com/abc-defg-hij?hs=224"))
    }

    @Test func 会議のURLは予定のURL場所メモの順に探す() throws {
        let event = try mapper.event(from: value(
            location: "https://zoom.us/j/1", notes: "https://meet.google.com/abc", url: URL(string: "https://teams.microsoft.com/l/x")
        ))
        #expect(event.meetingURL == URL(string: "https://teams.microsoft.com/l/x"))

        let fromLocation = try mapper.event(from: value(location: "https://zoom.us/j/1", notes: "https://meet.google.com/abc"))
        #expect(fromLocation.meetingURL == URL(string: "https://zoom.us/j/1"))
    }

    @Test func 会議サービスでないURLを飛ばして次の候補から会議のURLを探す() throws {
        let event = try mapper.event(from: value(
            notes: "https://example.com/agenda と https://zoom.us/j/1", url: URL(string: "https://example.com/event")
        ))
        #expect(event.meetingURL == URL(string: "https://zoom.us/j/1"))
    }

    @Test func メモのURLの末尾の句読点は含めない() {
        #expect(EventKitMapper.urls(in: "参加は https://meet.google.com/abc-defg-hij. よろしく") == [URL(string: "https://meet.google.com/abc-defg-hij")!])
        #expect(EventKitMapper.urls(in: "<a href=\"https://zoom.us/j/1\">link</a>") == [URL(string: "https://zoom.us/j/1")!])
    }

    @Test func 会議のURLがなければnilにする() throws {
        #expect(try mapper.event(from: value(notes: "会議室で実施")).meetingURL == nil)
    }

    // MARK: - 詳細の URL

    @Test func 予定のURLがhttpsで会議のURLと違うときだけ詳細のURLにする() throws {
        let detail = URL(string: "https://example.com/events/1")!
        #expect(try mapper.event(from: value(url: detail)).detailURL == detail)
        // 会議のURLと同じなら詳細のURLにはしない。
        let meeting = URL(string: "https://meet.google.com/abc")!
        let event = try mapper.event(from: value(url: meeting))
        #expect(event.meetingURL == meeting)
        #expect(event.detailURL == nil)
        // http と https 以外は詳細のURLにしない。
        #expect(try mapper.event(from: value(url: URL(string: "file:///tmp/a"))).detailURL == nil)
        #expect(try mapper.event(from: value(url: nil)).detailURL == nil)
    }

    // MARK: - その他の属性

    @Test func タイトルがなければ空にし場所は空白を取り除く() throws {
        #expect(try mapper.event(from: value(title: nil)).title == "")
        #expect(try mapper.event(from: value(location: "  会議室 A \n")).location == "会議室 A")
        #expect(try mapper.event(from: value(location: "  ")).location == nil)
    }

    // MARK: - メモ

    static let googleDelimiter = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"

    @Test func Googleの会議情報のブロックをメモから取り除く() throws {
        let notes = """
        議題の共有です。

        \(Self.googleDelimiter)
        Google Meet に参加: https://meet.google.com/abc-defg-hij
        または電話: +81 3-1234-5678
        \(Self.googleDelimiter)
        """
        let event = try mapper.event(from: value(notes: notes))
        #expect(event.notes == "議題の共有です。")
        // 会議の URL は、ブロックを取り除く前のメモで判定する。
        #expect(event.meetingURL == URL(string: "https://meet.google.com/abc-defg-hij"))
    }

    @Test func ブロックの前後の本文は残す() {
        let notes = "前\n\(Self.googleDelimiter)\n会議の情報\n\(Self.googleDelimiter)\n後"
        #expect(EventKitMapper.cleanedNotes(notes) == "前\n後")
    }

    @Test func 複数のブロックをそれぞれ取り除く() {
        let notes = "A\n\(Self.googleDelimiter)\nx\n\(Self.googleDelimiter)\nB\n\(Self.googleDelimiter)\ny\n\(Self.googleDelimiter)\nC"
        #expect(EventKitMapper.cleanedNotes(notes) == "A\nB\nC")
    }

    @Test func 対になる区切り線がなければ取り除かない() {
        let notes = "本文\n\(Self.googleDelimiter)\n続き"
        #expect(EventKitMapper.cleanedNotes(notes) == notes)
    }

    @Test func 区切り線に似た行でも形が違えば取り除かない() {
        let notes = "-:: 見出し ::-\n本文\n-::~ 見出し"
        #expect(EventKitMapper.cleanedNotes(notes) == notes)
    }

    @Test func 空行が3行以上続いたら1行の空行にまとめる() {
        #expect(EventKitMapper.cleanedNotes("A\n\n\n\nB") == "A\n\nB")
        #expect(EventKitMapper.cleanedNotes("A\n \n\t\n\n\nB") == "A\n\nB")
        // 2 行までの空行はそのままにする。
        #expect(EventKitMapper.cleanedNotes("A\n\n\nB") == "A\n\n\nB")
        #expect(EventKitMapper.cleanedNotes("A\n\nB") == "A\n\nB")
    }

    @Test func ブロックを取り除いた跡の空行もまとめる() {
        let notes = "A\n\n\n\(Self.googleDelimiter)\nx\n\(Self.googleDelimiter)\n\n\nB"
        #expect(EventKitMapper.cleanedNotes(notes) == "A\n\nB")
    }

    @Test func メモの前後の空白を取り除く() {
        #expect(EventKitMapper.cleanedNotes("\n\n  本文  \n\n") == "本文")
    }

    @Test func 改行のCRLFをLFにそろえる() {
        #expect(EventKitMapper.cleanedNotes("A\r\n\r\n\r\n\r\nB") == "A\n\nB")
    }

    @Test func メモが空またはブロックだけならnilにする() throws {
        #expect(EventKitMapper.cleanedNotes(nil) == nil)
        #expect(EventKitMapper.cleanedNotes("  \n ") == nil)
        #expect(EventKitMapper.cleanedNotes("\(Self.googleDelimiter)\nx\n\(Self.googleDelimiter)") == nil)
        #expect(try mapper.event(from: value(notes: nil)).notes == nil)
    }

    // MARK: - 参加者

    func participant(
        _ name: String?, _ address: String? = nil, status: EventKitParticipantStatus = .accepted, me: Bool = false
    ) -> EventKitParticipantValue {
        EventKitParticipantValue(
            name: name, url: address.flatMap { URL(string: "mailto:\($0)") }, status: status, isCurrentUser: me
        )
    }

    @Test func 参加者の名前とメールアドレスと出欠と自分かを変換する() throws {
        let event = try mapper.event(from: value(attendees: [
            participant("山田 太郎", "yamada@example.com", status: .tentative),
            participant("自分", "me@example.com", status: .pending, me: true),
        ]))
        #expect(event.participants == [
            try EventParticipant(name: "山田 太郎", emailAddress: "yamada@example.com", attendance: .tentative),
            try EventParticipant(name: "自分", emailAddress: "me@example.com", attendance: .needsAction, isCurrentUser: true),
        ])
        #expect(event.participants.map(\.isOrganizer) == [false, false])
        #expect(event.participants.map(\.isCurrentUser) == [false, true])
    }

    @Test func メールアドレスはmailtoのURLからだけ取る() {
        #expect(EventKitMapper.emailAddress(of: URL(string: "mailto:a@example.com")) == "a@example.com")
        #expect(EventKitMapper.emailAddress(of: URL(string: "MAILTO:A@Example.com")) == "A@Example.com")
        #expect(EventKitMapper.emailAddress(of: URL(string: "mailto:a%2Bb@example.com")) == "a+b@example.com")
        #expect(EventKitMapper.emailAddress(of: URL(string: "https://example.com/principals/a")) == nil)
        #expect(EventKitMapper.emailAddress(of: URL(string: "/principals/users/a")) == nil)
        #expect(EventKitMapper.emailAddress(of: nil) == nil)
    }

    @Test func mailtoでないURLの参加者は名前だけにする() throws {
        let event = try mapper.event(from: value(attendees: [
            EventKitParticipantValue(
                name: "山田", url: URL(string: "https://example.com/principals/a"), status: .accepted, isCurrentUser: false
            ),
        ]))
        #expect(event.participants.first?.emailAddress == nil)
        #expect(event.participants.first?.name == "山田")
    }

    @Test func 名前もメールアドレスもない参加者は除く() throws {
        let event = try mapper.event(from: value(attendees: [
            participant(nil, nil), participant("  ", nil), participant(nil, "only@example.com"),
        ]))
        #expect(event.participants.map(\.displayName) == ["only@example.com"])
    }

    @Test func 主催者を先頭に置く() throws {
        let event = try mapper.event(from: value(
            organizer: participant("主催者", "host@example.com"),
            attendees: [participant("A", "a@example.com")]
        ))
        #expect(event.participants.map(\.displayName) == ["主催者", "A"])
        #expect(event.participants.map(\.isOrganizer) == [true, false])
    }

    @Test func 主催者が参加者にもいれば1人にまとめる() throws {
        let event = try mapper.event(from: value(
            organizer: participant("主催者", "Host@Example.com", status: .unknown),
            attendees: [
                participant("A", "a@example.com", status: .declined),
                participant("主催者", "host@example.com", status: .accepted, me: true),
                participant("B", "b@example.com"),
            ]
        ))
        #expect(event.participants.map(\.displayName) == ["主催者", "A", "B"])
        let host = try #require(event.participants.first)
        #expect(host.isOrganizer)
        // 参加者の側の出欠と、自分かを引き継ぐ。
        #expect(host.attendance == .accepted)
        #expect(host.isCurrentUser)
        #expect(event.participants.filter(\.isOrganizer).count == 1)
    }

    @Test func メールアドレスがなければ名前で主催者をまとめる() throws {
        let event = try mapper.event(from: value(
            organizer: participant("主催者"),
            attendees: [participant("主催者"), participant("A")]
        ))
        #expect(event.participants.map(\.displayName) == ["主催者", "A"])
    }

    @Test func 主催者の名前が空なら参加者の側の名前で補う() throws {
        let event = try mapper.event(from: value(
            organizer: participant(nil, "host@example.com"),
            attendees: [participant("主催者", "host@example.com")]
        ))
        #expect(event.participants.count == 1)
        #expect(event.participants.first?.name == "主催者")
        #expect(event.participants.first?.emailAddress == "host@example.com")
    }

    @Test func 主催者だけの予定でも主催者を参加者に含める() throws {
        let event = try mapper.event(from: value(organizer: participant("主催者", "host@example.com")))
        #expect(event.participants.map(\.displayName) == ["主催者"])
        #expect(event.participants.first?.isOrganizer == true)
    }

    @Test func 主催者も参加者もいなければ参加者は空にする() throws {
        #expect(try mapper.event(from: value()).participants.isEmpty)
    }

    @Test func 識別子が空の予定は変換に失敗する() {
        #expect(throws: DomainError.emptyIdentifier) {
            try mapper.event(from: EventKitEventValue(
                eventIdentifier: nil, calendarItemIdentifier: "item", calendarItemExternalIdentifier: nil,
                calendarIdentifier: "", sourceIdentifier: "source", title: nil,
                startDate: date(2026, 10, 24), endDate: date(2026, 10, 24, 1), isAllDay: false,
                location: nil, notes: nil, url: nil, currentUserStatus: nil, organizer: nil, attendees: []
            ))
        }
    }
}

@Suite struct WorkspaceSystemSettingsOpenerTests {
    @MainActor
    @Test func システム設定のURLを返す() {
        #expect(WorkspaceSystemSettingsOpener.url(for: .calendarPrivacy).absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        #expect(WorkspaceSystemSettingsOpener.url(for: .internetAccounts).absoluteString
            == "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
    }
}
