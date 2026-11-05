import EventKit
import Foundation
import BarlunariApplication
import BarlunariDomain

/// `EKEventStore` を 1 つ持ち、カレンダー・予定・許可・同期・出欠の回答の 5 つのポートを実装する。
///
/// `EKEventStore` と `EKEvent` などは `Sendable` ではないため、actor に閉じ込める。
/// 外へ返すのは、EventKit に依存しない値と、それを `EventKitMapper` で変換したドメインの型だけである。
public actor EventKitCalendarStore: CalendarRepository, CalendarEventRepository, CalendarAccessAuthorizer, CalendarSourceRefresher, EventResponder {
    private let store = EKEventStore()
    private let mapper: EventKitMapper
    private let dateProvider: any DateProvider
    private let changeObserver: StoreChangeObserver

    public init(dateProvider: any DateProvider) {
        self.dateProvider = dateProvider
        mapper = EventKitMapper(dateProvider: dateProvider)
        changeObserver = StoreChangeObserver()
        changeObserver.start(observing: store)
    }

    // MARK: - CalendarAccessAuthorizer

    public func status() async -> CalendarAuthorizationStatus {
        Self.currentStatus()
    }

    /// 完全アクセスを求める。許可されたら、許可の前に作った store が空の結果を返し続けないよう `reset()` する。
    public func requestAccess() async throws -> CalendarAuthorizationStatus {
        let store = self.store
        let granted: Bool = try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        if granted { store.reset() }
        return Self.currentStatus()
    }

    /// 書き込みだけの許可と制限は、予定を読めないため `denied` にする。
    private static func currentStatus() -> CalendarAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        default: .denied
        }
    }

    // MARK: - CalendarSourceRefresher

    /// 完全アクセスのときだけ、サーバーとの同期を OS に求める。許可がなければ何もせず、ダイアログも出さない。
    public func refreshSources() async {
        guard Self.currentStatus() == .fullAccess else { return }
        store.refreshSourcesIfNecessary()
    }

    // MARK: - CalendarRepository

    public func accounts() async throws -> [UserAccount] {
        try Self.requireFullAccess()
        var seen = Set<String>()
        var accounts: [UserAccount] = []
        for source in eventCalendars().compactMap(\.source) where seen.insert(source.sourceIdentifier).inserted {
            // 識別子か名前が空の source は、アカウントとして扱えないため除く。
            if let account = try? mapper.account(from: EventKitSourceValue(
                sourceIdentifier: source.sourceIdentifier, title: source.title
            )) {
                accounts.append(account)
            }
        }
        return accounts.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    public func calendars() async throws -> [UserCalendar] {
        try Self.requireFullAccess()
        return eventCalendars().compactMap { calendar in
            try? mapper.calendar(from: Self.value(of: calendar))
        }
    }

    // MARK: - CalendarEventRepository

    public func events(in interval: DateInterval, calendars: Set<UserCalendar.Identity>) async throws -> [CalendarEvent] {
        try Self.requireFullAccess()
        let selected = eventCalendars().filter { calendar in
            Self.identity(of: calendar).map(calendars.contains) ?? false
        }
        guard !selected.isEmpty else {
            logFetch(calendarCount: 0, eventCount: 0, withoutUIDCount: 0)
            return []
        }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: selected)
        let values = store.events(matching: predicate).compactMap(Self.value(of:))
        let events = values.compactMap { try? mapper.event(from: $0) }
        logFetch(
            calendarCount: selected.count,
            eventCount: events.count,
            withoutUIDCount: events.filter { $0.iCalendarUID == nil }.count
        )
        return events
    }

    /// 重複の除去が実機で効いているか、`log` コマンドで確かめるための記録。予定の内容は記録しない。
    private func logFetch(calendarCount: Int, eventCount: Int, withoutUIDCount: Int) {
        Log.calendar.info(
            "予定を取得した: カレンダー \(calendarCount, privacy: .public) 件、予定 \(eventCount, privacy: .public) 件、UID なし \(withoutUIDCount, privacy: .public) 件"
        )
    }

    // MARK: - EventResponder

    /// 自分の出欠を変えて、表示している回だけ（`.thisEvent`）に保存する。
    ///
    /// `EKParticipant.participantStatus` は公開 API では読み取り専用である。`attendees` が返す実際のインスタンスは
    /// 非公開のサブクラスで、`setParticipantStatus:` に応答するときだけ KVC で書く。応答しなければ書かずに `unsupported` を投げる。
    public func respond(
        to identity: CalendarEvent.Identity, with response: AttendanceResponse
    ) async throws -> EventResponseOutcome {
        try Self.requireFullAccess()
        guard let event = findEvent(identity) else { throw EventResponseError.eventNotFound }
        guard let me = event.attendees?.first(where: \.isCurrentUser), event.organizer?.isCurrentUser != true else {
            throw EventResponseError.notRespondable
        }
        guard me.responds(to: Selector(("setParticipantStatus:"))) else {
            Log.calendar.error("出欠の回答に失敗した: この macOS では参加者の出欠を書き込めない")
            throw EventResponseError.unsupported
        }
        let status = Self.participantStatus(of: response)

        // 繰り返しの予定でまだ切り離されていない回は、アラームがあると保存が Access Denied で失敗する。
        // アラームを外して保存し、外す前に複製しておいたアラームを付け直してもう一度保存する。
        // 複製は `proximity`、`structuredLocation`、`soundName` などの設定も保つ。複製できないアラームがあれば、外さずに保存を試みる。
        let alarms = event.alarms ?? []
        let copies = alarms.compactMap { $0.copy() as? EKAlarm }
        let removesAlarms = event.hasRecurrenceRules && !event.isDetached && !alarms.isEmpty && copies.count == alarms.count
        do {
            if removesAlarms { event.alarms = nil }
            me.setValue(status.rawValue, forKey: "participantStatus")
            guard me.participantStatus == status else {
                event.refresh()
                throw EventResponseError.unsupported
            }
            try store.save(event, span: .thisEvent)
        } catch let error as EventResponseError {
            throw error
        } catch {
            event.refresh()
            let nsError = error as NSError
            Log.calendar.error(
                "出欠の回答に失敗した: 保存できなかった domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            throw EventResponseError.saveFailed
        }
        guard removesAlarms else { return .saved }
        return restoreAlarms(copies, on: event)
    }

    /// 外したアラームの複製を付け直して保存する。回答は保存済みなので、失敗しても回答の失敗にはせず、`.savedWithoutAlarms` を返す。
    private func restoreAlarms(_ alarms: [EKAlarm], on event: EKEvent) -> EventResponseOutcome {
        alarms.forEach(event.addAlarm)
        do {
            try store.save(event, span: .thisEvent)
            return .saved
        } catch {
            event.refresh()
            let nsError = error as NSError
            Log.calendar.error(
                "アラームを付け直せなかった domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            return .savedWithoutAlarms
        }
    }

    private static func participantStatus(of response: AttendanceResponse) -> EKParticipantStatus {
        switch response {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        }
    }

    /// 標準のカレンダーアプリで予定を開く URL。予定が見つからなければ `nil`。
    public func calendarAppURL(for identity: CalendarEvent.Identity) async -> URL? {
        guard Self.currentStatus() == .fullAccess, let event = findEvent(identity), let start = event.startDate else { return nil }
        return CalendarAppURL.url(
            calendarItemIdentifier: event.calendarItemIdentifier,
            startDate: start,
            isAllDay: event.isAllDay,
            hasRecurrenceRules: event.hasRecurrenceRules,
            calendar: dateProvider.calendar
        )
    }

    /// アカウント・カレンダー・回の開始日時が一致する予定。ID だけでは同一視しない。
    private func findEvent(_ identity: CalendarEvent.Identity) -> EKEvent? {
        guard let locator = EventKitEventLocator(identity) else { return nil }
        let calendars = eventCalendars().filter {
            $0.calendarIdentifier == locator.calendarIdentifier && $0.source?.sourceIdentifier == locator.sourceIdentifier
        }
        guard !calendars.isEmpty else { return nil }
        let interval = locator.searchInterval
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate).first {
            guard let start = $0.startDate else { return false }
            return locator.matches(identifier: $0.eventIdentifier, calendarItemIdentifier: $0.calendarItemIdentifier, startDate: start)
        }
    }

    // MARK: - EventKit の型の読み取り

    private static func requireFullAccess() throws {
        switch currentStatus() {
        case .notDetermined: throw CalendarAccessError.notDetermined
        case .denied: throw CalendarAccessError.denied
        case .fullAccess: break
        }
    }

    private func eventCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    /// 識別子が空で ID を作れないカレンダーは `nil`。EventKit が空の識別子を返すことはない。
    private static func identity(of calendar: EKCalendar) -> UserCalendar.Identity? {
        guard let source = calendar.source,
              let accountID = try? AccountID(source.sourceIdentifier),
              let calendarID = try? CalendarID(calendar.calendarIdentifier)
        else { return nil }
        return UserCalendar.Identity(accountID: accountID, calendarID: calendarID)
    }

    private static func value(of calendar: EKCalendar) -> EventKitCalendarValue {
        EventKitCalendarValue(
            calendarIdentifier: calendar.calendarIdentifier,
            title: calendar.title,
            sourceIdentifier: calendar.source?.sourceIdentifier ?? "",
            color: calendar.cgColor.flatMap(srgbValue(of:))
        )
    }

    private static func srgbValue(of color: CGColor) -> EventKitColorValue? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3
        else { return nil }
        return EventKitColorValue(red: components[0], green: components[1], blue: components[2])
    }

    private static func value(of event: EKEvent) -> EventKitEventValue? {
        guard let calendar = event.calendar, let source = calendar.source,
              let start = event.startDate, let end = event.endDate
        else { return nil }
        let currentUser = event.attendees?.first(where: \.isCurrentUser)
        return EventKitEventValue(
            eventIdentifier: event.eventIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
            calendarIdentifier: calendar.calendarIdentifier,
            sourceIdentifier: source.sourceIdentifier,
            title: event.title,
            startDate: start,
            endDate: end,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url,
            currentUserStatus: currentUser.map { participantStatus(of: $0.participantStatus) },
            organizer: event.organizer.map(value(of:)),
            attendees: (event.attendees ?? []).map(value(of:))
        )
    }

    private static func value(of participant: EKParticipant) -> EventKitParticipantValue {
        EventKitParticipantValue(
            name: participant.name,
            url: participant.url,
            status: participantStatus(of: participant.participantStatus),
            isCurrentUser: participant.isCurrentUser
        )
    }

    private static func participantStatus(of status: EKParticipantStatus) -> EventKitParticipantStatus {
        switch status {
        case .unknown: .unknown
        case .pending: .pending
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        case .delegated: .delegated
        case .completed: .completed
        case .inProcess: .inProcess
        @unknown default: .unknown
        }
    }
}

/// `EKEventStoreChanged` を受けて、Application の `calendarStoreDidChange` を送る。解放時に購読を解除する。
private final class StoreChangeObserver: @unchecked Sendable {
    private var token: (any NSObjectProtocol)?

    func start(observing store: EKEventStore) {
        token = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: nil
        ) { _ in
            NotificationCenter.default.post(name: .calendarStoreDidChange, object: nil)
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
