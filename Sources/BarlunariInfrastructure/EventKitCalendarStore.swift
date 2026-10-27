import EventKit
import Foundation
import BarlunariApplication
import BarlunariDomain

/// `EKEventStore` を 1 つ持ち、カレンダー・予定・許可の 3 つのポートを実装する。
///
/// `EKEventStore` と `EKEvent` などは `Sendable` ではないため、actor に閉じ込める。
/// 外へ返すのは、EventKit に依存しない値と、それを `EventKitMapper` で変換したドメインの型だけである。
public actor EventKitCalendarStore: CalendarRepository, CalendarEventRepository, CalendarAccessAuthorizer {
    private let store = EKEventStore()
    private let mapper: EventKitMapper
    private let changeObserver: StoreChangeObserver

    public init(dateProvider: any DateProvider) {
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
