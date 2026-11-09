import AppKit
import BarlunariApplication
import BarlunariDomain
import BarlunariInfrastructure
import BarlunariPresentation

/// コンポジションルート。具象型の生成と依存の組み立ては、ここでだけ行う。
@MainActor
final class AppContainer {
    let popoverViewModel: CalendarPopoverViewModel
    let settingsViewModel: SettingsViewModel

    init() {
        // 設定の「週の始まり」を保存する。ポップオーバーと設定画面に同じ保存先を渡す。
        let firstWeekdayStore = UserDefaultsFirstWeekdayStore()
        // 保存した曜日があれば、システムの暦の週の開始曜日を置き換える。暦を使うすべての処理が同じ日付の提供元を使う。
        let dateProvider = FirstWeekdayOverridingDateProvider(base: SystemDateProvider(), store: firstWeekdayStore)
        // EKEventStore は 1 つだけ持つ。カレンダー・予定・許可・同期・出欠の回答の 5 つのポートを同じインスタンスが実装する。
        let calendarStore = EventKitCalendarStore(dateProvider: dateProvider)
        let urlOpener = WorkspaceURLOpener()
        let systemSettingsOpener = WorkspaceSystemSettingsOpener()
        let visibilityRepository = UserDefaultsCalendarVisibilityRepository()
        let displayModeStore = UserDefaultsDisplayModeStore()
        let showDeclinedEventsStore = UserDefaultsShowDeclinedEventsStore()
        let launchAtLoginService = SMAppServiceLaunchAtLoginService()

        let requestCalendarAccess = RequestCalendarAccessUseCase(authorizer: calendarStore)
        let openSystemSettings = OpenSystemSettingsUseCase(opener: systemSettingsOpener)
        // ポップオーバーと設定画面で共有し、設定の変更をポップオーバーの再読み込みにつなぐ。
        let changeNotifier = DataChangeNotifier()
        // ポップオーバーの「表示するカレンダー」の一覧と設定画面のカレンダータブで共有する。
        let listCalendars = ListCalendarsUseCase(
            authorizer: calendarStore,
            calendarRepository: calendarStore,
            visibilityRepository: visibilityRepository
        )
        let setCalendarVisibility = SetCalendarVisibilityUseCase(visibilityRepository: visibilityRepository)

        popoverViewModel = CalendarPopoverViewModel(
            loadAgenda: LoadAgendaUseCase(
                authorizer: calendarStore,
                calendarRepository: calendarStore,
                eventRepository: calendarStore,
                visibilityRepository: visibilityRepository,
                showDeclinedEventsStore: showDeclinedEventsStore,
                dateProvider: dateProvider
            ),
            requestCalendarAccess: requestCalendarAccess,
            openSystemSettings: openSystemSettings,
            refreshCalendarSources: RefreshCalendarSourcesUseCase(refresher: calendarStore),
            respondToEvent: RespondToEventUseCase(responder: calendarStore),
            openEventInCalendarApp: OpenEventInCalendarAppUseCase(
                opener: EventKitCalendarAppOpener(store: calendarStore, urlOpener: urlOpener)
            ),
            dateProvider: dateProvider,
            urlOpener: urlOpener,
            changeNotifier: changeNotifier,
            loadDisplayMode: LoadDisplayModeUseCase(store: displayModeStore),
            saveDisplayMode: SaveDisplayModeUseCase(store: displayModeStore),
            listCalendars: listCalendars,
            setCalendarVisibility: setCalendarVisibility,
            workspaceNotificationCenter: NSWorkspace.shared.notificationCenter
        )
        settingsViewModel = SettingsViewModel(
            getLaunchAtLogin: GetLaunchAtLoginUseCase(service: launchAtLoginService),
            setLaunchAtLogin: SetLaunchAtLoginUseCase(service: launchAtLoginService),
            loadShowDeclinedEvents: LoadShowDeclinedEventsUseCase(store: showDeclinedEventsStore),
            saveShowDeclinedEvents: SaveShowDeclinedEventsUseCase(store: showDeclinedEventsStore),
            loadFirstWeekday: LoadFirstWeekdayUseCase(store: firstWeekdayStore),
            saveFirstWeekday: SaveFirstWeekdayUseCase(store: firstWeekdayStore),
            listCalendars: listCalendars,
            setCalendarVisibility: setCalendarVisibility,
            requestCalendarAccess: requestCalendarAccess,
            openSystemSettings: openSystemSettings,
            changeNotifier: changeNotifier
        )
    }
}
