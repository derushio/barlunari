import Foundation
import MenuDateApplication
import MenuDateDomain

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
