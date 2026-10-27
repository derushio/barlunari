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
        let dateProvider = SystemDateProvider()
        // EKEventStore は 1 つだけ持つ。カレンダー・予定・許可の 3 つのポートを同じインスタンスが実装する。
        let calendarStore = EventKitCalendarStore(dateProvider: dateProvider)
        let urlOpener = WorkspaceURLOpener()
        let systemSettingsOpener = WorkspaceSystemSettingsOpener()
        let visibilityRepository = UserDefaultsCalendarVisibilityRepository()
        let displayModeStore = UserDefaultsDisplayModeStore()
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
                dateProvider: dateProvider
            ),
            requestCalendarAccess: requestCalendarAccess,
            openSystemSettings: openSystemSettings,
            dateProvider: dateProvider,
            urlOpener: urlOpener,
            changeNotifier: changeNotifier,
            loadDisplayMode: LoadDisplayModeUseCase(store: displayModeStore),
            saveDisplayMode: SaveDisplayModeUseCase(store: displayModeStore),
            listCalendars: listCalendars,
            setCalendarVisibility: setCalendarVisibility
        )
        settingsViewModel = SettingsViewModel(
            getLaunchAtLogin: GetLaunchAtLoginUseCase(service: launchAtLoginService),
            setLaunchAtLogin: SetLaunchAtLoginUseCase(service: launchAtLoginService),
            listCalendars: listCalendars,
            setCalendarVisibility: setCalendarVisibility,
            requestCalendarAccess: requestCalendarAccess,
            openSystemSettings: openSystemSettings,
            changeNotifier: changeNotifier
        )
    }
}
