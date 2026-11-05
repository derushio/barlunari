import Foundation
import BarlunariApplication
import BarlunariDomain
import Synchronization

public struct FixedDateProvider: DateProvider {
    public let now: Date
    public let calendar: Calendar

    public init(now: Date = SampleData.now, calendar: Calendar = SampleData.calendar) {
        self.now = now
        self.calendar = calendar
    }
}

/// 許可の状態を保持するだけのフェイク。`requestAccess()` は `statusAfterRequest` に状態を変える。
///
/// 状態が `notDetermined` のときだけ状態を変える。許可を求めた回数は `requestCount` に記録する。
/// `requestError` を設定すると、`requestAccess()` がそのエラーで失敗する。
public actor FakeCalendarAccessAuthorizer: CalendarAccessAuthorizer {
    public private(set) var currentStatus: CalendarAuthorizationStatus
    public private(set) var requestCount = 0
    private let statusAfterRequest: CalendarAuthorizationStatus
    private let requestError: (any Error)?

    public init(
        status: CalendarAuthorizationStatus = .fullAccess,
        statusAfterRequest: CalendarAuthorizationStatus = .fullAccess,
        requestError: (any Error)? = nil
    ) {
        self.currentStatus = status
        self.statusAfterRequest = statusAfterRequest
        self.requestError = requestError
    }

    public func status() async -> CalendarAuthorizationStatus { currentStatus }

    public func requestAccess() async throws -> CalendarAuthorizationStatus {
        requestCount += 1
        if let requestError { throw requestError }
        if currentStatus == .notDetermined { currentStatus = statusAfterRequest }
        return currentStatus
    }
}

/// ログイン時の起動の状態を保持するだけのフェイク。`setEnabledError` を設定すると、変更が失敗する。
public actor FakeLaunchAtLoginService: LaunchAtLoginService {
    private var enabled: Bool
    private let setEnabledError: (any Error)?

    public init(isEnabled: Bool = false, setEnabledError: (any Error)? = nil) {
        self.enabled = isEnabled
        self.setEnabledError = setEnabledError
    }

    public func isEnabled() async -> Bool { enabled }

    public func setEnabled(_ enabled: Bool) async throws {
        if let setEnabledError { throw setEnabledError }
        self.enabled = enabled
    }
}

/// 渡された URL を記録するだけの `URLOpener`。
///
/// `result` を `false` にすると、開けなかったことにする。`onOpen` で、開いたときの副作用を差し込める。
@MainActor
public final class FakeURLOpener: URLOpener {
    public private(set) var openedURLs: [URL] = []
    private let result: Bool
    private let onOpen: (@MainActor @Sendable (URL) -> Void)?

    public init(result: Bool = true, onOpen: (@MainActor @Sendable (URL) -> Void)? = nil) {
        self.result = result
        self.onOpen = onOpen
    }

    public func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        onOpen?(url)
        return result
    }
}

/// 開いたシステム設定の画面を記録するだけの `SystemSettingsOpener`。`result` を `false` にすると、開けなかったことにする。
@MainActor
public final class FakeSystemSettingsOpener: SystemSettingsOpener {
    public private(set) var openedDestinations: [SystemSettingsDestination] = []
    private let result: Bool

    public init(result: Bool = true) {
        self.result = result
    }

    public func open(_ destination: SystemSettingsDestination) -> Bool {
        openedDestinations.append(destination)
        return result
    }
}

/// 同期を求められた回数を数える `CalendarSourceRefresher`。
///
/// `onRefresh` を渡すと、同期を求められるたびに実行する。サーバーにだけある予定がローカルに届く動きの再現に使う。
public final class FakeCalendarSourceRefresher: CalendarSourceRefresher {
    private let count = Mutex(0)
    private let onRefresh: (@Sendable () -> Void)?

    public init(onRefresh: (@Sendable () -> Void)? = nil) {
        self.onRefresh = onRefresh
    }

    public func refreshSources() async {
        count.withLock { $0 += 1 }
        onRefresh?()
    }

    /// 同期を求められた回数。
    public var refreshCount: Int { count.withLock { $0 } }
}

/// 回答を記録するだけの `EventResponder`。
///
/// `setFailure(_:)` で、以後の回答をそのエラーで失敗させる。`nil` を渡すと成功に戻る。
/// `onRespond` を渡すと、成功した回答のたびに実行する。予定のリポジトリに回答を反映する動きの再現に使う。
public final class FakeEventResponder: EventResponder {
    private struct State {
        var responses: [Recorded] = []
        var failure: (any Error)?
        var attempts = 0
    }

    public struct Recorded: Sendable, Equatable {
        public let event: CalendarEvent.Identity
        public let response: AttendanceResponse

        public init(event: CalendarEvent.Identity, response: AttendanceResponse) {
            self.event = event
            self.response = response
        }
    }

    private let state = Mutex(State())
    private let onRespond: (@Sendable (CalendarEvent.Identity, AttendanceResponse) -> Void)?

    public init(
        failure: (any Error)? = nil,
        onRespond: (@Sendable (CalendarEvent.Identity, AttendanceResponse) -> Void)? = nil
    ) {
        self.onRespond = onRespond
        state.withLock { $0.failure = failure }
    }

    public func setFailure(_ failure: (any Error)?) {
        state.withLock { $0.failure = failure }
    }

    /// 成功した回答を、呼ばれた順に並べたもの。失敗した回答は含まない。
    public var responses: [Recorded] { state.withLock { $0.responses } }

    /// 回答を受け付けた回数。失敗した回答も数える。
    public var attemptCount: Int { state.withLock { $0.attempts } }

    public func respond(to event: CalendarEvent.Identity, with response: AttendanceResponse) async throws {
        let failure = state.withLock { state -> (any Error)? in
            state.attempts += 1
            if state.failure == nil { state.responses.append(Recorded(event: event, response: response)) }
            return state.failure
        }
        if let failure { throw failure }
        onRespond?(event, response)
    }
}

/// 開いた予定を記録するだけの `CalendarAppOpener`。`result` を `false` にすると、開けなかったことにする。
public final class FakeCalendarAppOpener: CalendarAppOpener {
    private let state = Mutex<[CalendarEvent.Identity]>([])
    private let result: Bool

    public init(result: Bool = true) {
        self.result = result
    }

    public var openedEvents: [CalendarEvent.Identity] { state.withLock { $0 } }

    public func open(_ event: CalendarEvent.Identity) async -> Bool {
        state.withLock { $0.append(event) }
        return result
    }
}
