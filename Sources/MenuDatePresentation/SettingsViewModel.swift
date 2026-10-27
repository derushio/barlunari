import Foundation
import MenuDateApplication
import MenuDateDomain
import Observation

/// 設定画面の状態と操作。一般・カレンダーの 2 タブ分を持つ。
@MainActor
@Observable
public final class SettingsViewModel {
    public enum CalendarsPhase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        /// 許可の状態やカレンダーの有無により、一覧の代わりに案内を出す。
        case guide(CalendarAccessGuide)
        /// 利用者に見せる日本語の文を持つ。
        case failed(String)
    }

    // 一般
    public private(set) var launchAtLogin = false
    public private(set) var launchAtLoginError: String?

    // カレンダー
    public private(set) var calendars: [CalendarListItem] = []
    public private(set) var accounts: [UserAccount] = []
    public private(set) var calendarsPhase: CalendarsPhase = .idle
    public private(set) var calendarsError: String?
    /// 許可を求めている間は `true`。許可のダイアログは 1 つしか出せないため、続けて押されても求め直さない。
    public private(set) var isRequestingAccess = false

    /// この ViewModel が把握している `DataChangeNotifier` の版。これと違えば他の画面での変更である。
    private var observedRevision = 0
    /// 解放時に通知の購読を解除する。
    @ObservationIgnored private var observations: [NotificationObservation] = []

    private let getLaunchAtLogin: GetLaunchAtLoginUseCase
    private let setLaunchAtLoginUseCase: SetLaunchAtLoginUseCase
    private let listCalendars: ListCalendarsUseCase
    private let setCalendarVisibility: SetCalendarVisibilityUseCase
    private let requestCalendarAccess: RequestCalendarAccessUseCase
    private let openSystemSettings: OpenSystemSettingsUseCase
    private let changeNotifier: DataChangeNotifier

    public init(
        getLaunchAtLogin: GetLaunchAtLoginUseCase,
        setLaunchAtLogin: SetLaunchAtLoginUseCase,
        listCalendars: ListCalendarsUseCase,
        setCalendarVisibility: SetCalendarVisibilityUseCase,
        requestCalendarAccess: RequestCalendarAccessUseCase,
        openSystemSettings: OpenSystemSettingsUseCase,
        changeNotifier: DataChangeNotifier,
        notificationCenter: NotificationCenter = .default
    ) {
        self.getLaunchAtLogin = getLaunchAtLogin
        self.setLaunchAtLoginUseCase = setLaunchAtLogin
        self.listCalendars = listCalendars
        self.setCalendarVisibility = setCalendarVisibility
        self.requestCalendarAccess = requestCalendarAccess
        self.openSystemSettings = openSystemSettings
        self.changeNotifier = changeNotifier

        // カレンダーのデータが変わったら、一覧を読み直す。
        observations = [
            NotificationObservation(center: notificationCenter, name: .calendarStoreDidChange) { [weak self] _ in
                // queue に .main を指定しているため、メインスレッドで呼ばれる。
                MainActor.assumeIsolated { self?.reloadCalendarsInBackground() }
            },
        ]
    }

    /// アカウントごとに分けたカレンダーの一覧。アカウントの並び順で、カレンダーを持たないアカウントは含まない。
    public var calendarSections: [CalendarAccountSection] {
        CalendarAccountSection.sections(accounts: accounts, items: calendars)
    }

    /// ポップオーバーでの許可の操作などによる変更を示す版。View が変化を監視する。
    public var changeRevision: Int { changeNotifier.revision }

    /// 設定画面を開いたときに呼ぶ。すべてのタブの内容を最新にする。
    public func load() async {
        launchAtLogin = await getLaunchAtLogin.execute()
        observedRevision = changeNotifier.revision
        await reloadCalendars()
    }

    /// ポップオーバーなど他の画面で変更が通知されていれば、カレンダーの一覧を読み直す。自分で起こした変更では読み直さない。
    public func refreshIfChangedElsewhere() async {
        guard changeNotifier.revision != observedRevision else { return }
        observedRevision = changeNotifier.revision
        await reloadCalendars()
    }

    private func reloadCalendarsInBackground() {
        Task { await reloadCalendars() }
    }

    /// 自分で起こした変更を通知する。自分の通知で読み直さないよう、把握している版も進める。
    private func notifyChange() {
        changeNotifier.notifyChange()
        observedRevision = changeNotifier.revision
    }

    // MARK: - 一般

    /// 失敗したらトグルを元の値に戻し、エラーの文を出す。
    public func setLaunchAtLogin(_ enabled: Bool) async {
        let previous = launchAtLogin
        launchAtLogin = enabled
        launchAtLoginError = nil
        do {
            try await setLaunchAtLoginUseCase.execute(enabled: enabled)
        } catch {
            launchAtLogin = previous
            launchAtLoginError = "ログイン時の起動を変更できませんでした。"
        }
    }

    // MARK: - カレンダー

    public func reloadCalendars() async {
        calendarsError = nil
        // 読み込み済みの一覧は、読み直すあいだも出したままにする。
        if calendarsPhase != .loaded { calendarsPhase = .loading }
        do {
            let list = try await listCalendars.execute()
            accounts = list.accounts
            calendars = list.items
            calendarsPhase = list.items.isEmpty ? .guide(.noCalendars) : .loaded
        } catch {
            accounts = []
            calendars = []
            if let guide = (error as? CalendarAccessError).map(CalendarAccessGuide.init) {
                calendarsPhase = .guide(guide)
            } else {
                calendarsPhase = .failed(UserFacingMessage.text(for: error))
            }
        }
    }

    /// 案内のボタンを押したときの操作。許可の状態により、許可を求めるか、システム設定を開く。
    public func perform(_ guide: CalendarAccessGuide) async {
        switch guide {
        case .notDetermined:
            await requestAccess()
        case .denied:
            openSystemSettings.execute(.calendarPrivacy)
        case .noCalendars:
            openInternetAccounts()
        }
    }

    /// アカウントの追加と削除は、システム設定の「インターネットアカウント」で行う。
    public func openInternetAccounts() {
        openSystemSettings.execute(.internetAccounts)
    }

    /// 許可を求め、結果に合わせて一覧を読み直す。求めている間は何もしない。
    private func requestAccess() async {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        do {
            try await requestCalendarAccess.execute()
        } catch {
            calendarsPhase = .failed(UserFacingMessage.text(for: error))
            return
        }
        await reloadCalendars()
        notifyChange()
    }

    /// 画面の反応を速くするため先に表示を変え、失敗したら元に戻す。
    public func setVisibility(of calendarID: UserCalendar.Identity, isVisible: Bool) async {
        guard let index = calendars.firstIndex(where: { $0.id == calendarID }) else { return }
        let previous = calendars[index]
        calendars[index] = CalendarListItem(calendar: previous.calendar, isVisible: isVisible)
        calendarsError = nil
        do {
            try await setCalendarVisibility.execute(calendar: calendarID, isVisible: isVisible)
            notifyChange()
        } catch {
            if let current = calendars.firstIndex(where: { $0.id == calendarID }) {
                calendars[current] = previous
            }
            calendarsError = UserFacingMessage.text(for: error)
        }
    }
}
