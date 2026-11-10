import AppKit
import Foundation
import BarlunariApplication
import BarlunariDomain
import Observation
import OSLog

/// 取得の失敗のログ。予定の内容は出さず、エラーの型の名前だけを出す。
private let countdownLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Barlunari", category: "countdown")

/// メニューバーの項目に出す、次の予定までの残り時間。
///
/// パネルを開いていなくても動くよう、起動時（`start()`）から自分で予定を取得する。
/// 取得した予定はキャッシュし、表示の再計算は毎回キャッシュから行う。取得し直すのは次のときである。
/// - 起動時
/// - `.calendarStoreDidChange`、日付、タイムゾーン、システム時計の変更、スリープからの復帰
/// - `DataChangeNotifier.revision` の変化（カレンダーの表示切り替え、許可の結果、残り時間の対象の切り替え）
/// - 取得した範囲の残りが 24 時間を切ったとき
///
/// 取得は取り消せないため、取得中に取得し直しを求められたら、取り消さずに終わってから 1 回だけ取得し直す。
/// 変更通知による取得では、サーバーとの同期を求めない。
///
/// 表示の更新は、次の壁時計の分の境目と、`NextEventCountdown.nextChange` の早い方で行う。
@MainActor
@Observable
public final class MenuBarCountdownViewModel {
    /// 取得した範囲の終わりまでの残りがこの長さを切ったら、取得し直す。残り時間の対象の上限と同じ長さにする。
    static let refetchThreshold: TimeInterval = TimeInterval(NextEventCountdown.maximumRemainingMinutes) * 60
    /// 表示の更新を起こす時刻に付ける許容。OS がほかのタイマーとまとめて起こせるようにする。
    static let tickTolerance: Duration = .milliseconds(250)

    /// メニューバーに出す文字列。例は `01:25`。対象の予定がない、許可がない、取得に失敗したときは `nil`。
    public private(set) var displayText: String?
    /// VoiceOver に読ませる文。例は `次の予定まで1時間25分`。`displayText` が `nil` のときは `nil`。
    public private(set) var accessibilityLabel: String?

    private let loadUpcomingEvents: LoadUpcomingEventsUseCase
    private let dateProvider: any DateProvider
    private let changeNotifier: DataChangeNotifier
    private let workspaceNotificationCenter: NotificationCenter
    private let notificationCenter: NotificationCenter

    /// 取得した予定。取得に失敗した、または許可がないときは `nil`。
    @ObservationIgnored private var upcoming: UpcomingEvents?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isLoadInFlight = false
    /// 取得中に取得し直しを求められたら立てる。取得が終わったとき、立っていれば 1 回だけ取得し直す。
    @ObservationIgnored private var needsReloadAfterLoad = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var observations: [NotificationObservation] = []

    public init(
        loadUpcomingEvents: LoadUpcomingEventsUseCase,
        dateProvider: any DateProvider,
        changeNotifier: DataChangeNotifier,
        workspaceNotificationCenter: NotificationCenter,
        notificationCenter: NotificationCenter = .default
    ) {
        self.loadUpcomingEvents = loadUpcomingEvents
        self.dateProvider = dateProvider
        self.changeNotifier = changeNotifier
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.notificationCenter = notificationCenter
    }

    /// 通知の購読を始めて、最初の取得を行う。2 回目以降は何もしない。
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        let reload: @Sendable (ObjectIdentifier?) -> Void = { [weak self] _ in
            // queue に .main を指定しているため、メインスレッドで呼ばれる。
            MainActor.assumeIsolated { self?.requestReload() }
        }
        let names: [Notification.Name] = [
            .calendarStoreDidChange, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange,
        ]
        observations = names.map { NotificationObservation(center: notificationCenter, name: $0, handler: reload) }
        observations.append(
            NotificationObservation(center: workspaceNotificationCenter, name: NSWorkspace.didWakeNotification, handler: reload)
        )
        observeChangeNotifier()
        requestReload()
    }

    /// 現在時刻でキャッシュから表示を求め直す。取得した範囲の残りが 24 時間を切っていれば、取得し直しも求める。
    ///
    /// 時刻の提供元を進めたあとに呼ぶと、タイマーを待たずに表示が進む。
    public func recompute() {
        if let upcoming, upcoming.rangeEnd.timeIntervalSince(dateProvider.now) < Self.refetchThreshold {
            requestReload()
        }
        updateDisplay()
    }

    /// 進行中の取得と、その後に続く取得し直しの完了を待つ。テストと、完了後に処理を続けたい呼び出し側のためにある。
    public func waitForLoad() async {
        repeat { await loadTask?.value } while isLoadInFlight
    }

    // MARK: 取得

    private func requestReload() {
        if isLoadInFlight {
            needsReloadAfterLoad = true
            return
        }
        isLoadInFlight = true
        needsReloadAfterLoad = false
        loadTask = Task { [weak self] in
            await self?.performLoad()
        }
    }

    private func performLoad() async {
        do {
            upcoming = try await loadUpcomingEvents.execute()
        } catch {
            upcoming = nil
            // 許可がない、カレンダーがない場合は、利用者の状態であり異常ではない。表示を消すだけにする。
            if !(error is CalendarAccessError) {
                countdownLog.error("取得に失敗 error=\(String(describing: type(of: error)), privacy: .public)")
            }
        }
        isLoadInFlight = false
        updateDisplay()
        if needsReloadAfterLoad { requestReload() }
    }

    // MARK: 表示

    private func updateDisplay() {
        let now = dateProvider.now
        let countdown = upcoming?.countdown(at: now)
        let text = countdown.map { Self.text(for: $0) }
        let label = countdown.map { Self.accessibilityLabel(for: $0) }
        if displayText != text { displayText = text }
        if accessibilityLabel != label { accessibilityLabel = label }
        scheduleTick(after: now, countdown: countdown)
    }

    /// 次の壁時計の分の境目と、表示が次に変わる時刻の早い方に、再計算を予約する。
    private func scheduleTick(after now: Date, countdown: NextEventCountdown?) {
        tickTask?.cancel()
        let nowSeconds = now.timeIntervalSince1970
        var target = (nowSeconds / 60).rounded(.down) * 60 + 60
        if let countdown { target = min(target, countdown.nextChange.timeIntervalSince1970) }
        // 境目の直前に起きて同じ表示を求め直し続けないよう、短すぎる待ちは避ける。
        let delay = max(target - nowSeconds, 0.05)
        tickTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay), tolerance: Self.tickTolerance)
            } catch {
                return
            }
            self?.recompute()
        }
    }

    /// 例は `01:25`。
    static func text(for countdown: NextEventCountdown) -> String {
        String(format: "%02d:%02d", countdown.hours, countdown.minutes)
    }

    /// 例は `次の予定まで1時間25分`、`次の予定まで25分`、`次の予定まで2時間`。
    static func accessibilityLabel(for countdown: NextEventCountdown) -> String {
        switch (countdown.hours, countdown.minutes) {
        case (0, let minutes): "次の予定まで\(minutes)分"
        case (let hours, 0): "次の予定まで\(hours)時間"
        case (let hours, let minutes): "次の予定まで\(hours)時間\(minutes)分"
        }
    }

    // MARK: 変更通知

    /// `DataChangeNotifier.revision` の変化を追い、変わるたびに取得し直す。
    private func observeChangeNotifier() {
        withObservationTracking {
            _ = changeNotifier.revision
        } onChange: { [weak self] in
            // onChange は変更の直前に呼ばれる。メインアクターに移ってから読み直すと、新しい値になっている。
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.requestReload()
                self.observeChangeNotifier()
            }
        }
    }
}
