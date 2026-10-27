import Foundation
import MenuDateApplication
import MenuDateDomain
import Synchronization

/// 失敗を注入できるインメモリのリポジトリ群。`error` を設定すると、取得系の呼び出しがそのエラーで失敗する。
public struct InMemoryCalendarRepository: CalendarRepository {
    private let storedAccounts: [UserAccount]
    private let items: [UserCalendar]
    private let error: (any Error)?

    public init(
        accounts: [UserAccount] = SampleData.accounts,
        calendars: [UserCalendar] = SampleData.calendars,
        error: (any Error)? = nil
    ) {
        self.storedAccounts = accounts
        self.items = calendars
        self.error = error
    }

    public func accounts() async throws -> [UserAccount] {
        if let error { throw error }
        return storedAccounts
    }

    public func calendars() async throws -> [UserCalendar] {
        if let error { throw error }
        return items
    }
}

public struct InMemoryCalendarEventRepository: CalendarEventRepository {
    private let items: [CalendarEvent]
    private let error: (any Error)?

    public init(events: [CalendarEvent] = SampleData.events, error: (any Error)? = nil) {
        self.items = events
        self.error = error
    }

    public func events(in interval: DateInterval, calendars: Set<UserCalendar.Identity>) async throws -> [CalendarEvent] {
        if let error { throw error }
        return items.filter { event in
            guard calendars.contains(event.calendarIdentity) else { return false }
            switch event.schedule {
            case .allDay(let range):
                let eventInterval = range.dateInterval(calendar: SampleData.calendar)
                return eventInterval.start < interval.end && eventInterval.end > interval.start
            case .timed(let eventInterval):
                return eventInterval.start < interval.end
                    && (eventInterval.end > interval.start || eventInterval.duration == 0 && eventInterval.start >= interval.start)
            }
        }
    }
}

public actor InMemoryCalendarVisibilityRepository: CalendarVisibilityRepository {
    private var visibility: CalendarVisibility

    public init(visibility: CalendarVisibility = CalendarVisibility()) {
        self.visibility = visibility
    }

    public func load() async -> CalendarVisibility { visibility }
    public func update(_ body: @Sendable (inout CalendarVisibility) -> Void) async { body(&visibility) }
}

/// 保存した値を記録するインメモリの表示モードの保存先。
public final class InMemoryDisplayModeStore: DisplayModeStore {
    private struct State {
        var mode: CalendarDisplayMode?
        var savedModes: [CalendarDisplayMode] = []
    }

    private let state: Mutex<State>

    public init(mode: CalendarDisplayMode? = nil) {
        state = Mutex(State(mode: mode))
    }

    public func load() -> CalendarDisplayMode? { state.withLock { $0.mode } }

    public func save(_ mode: CalendarDisplayMode) {
        state.withLock {
            $0.mode = mode
            $0.savedModes.append(mode)
        }
    }

    /// `save` で保存したモードを、呼ばれた順に並べたもの。初期値は含まない。
    public var savedModes: [CalendarDisplayMode] { state.withLock { $0.savedModes } }
}
