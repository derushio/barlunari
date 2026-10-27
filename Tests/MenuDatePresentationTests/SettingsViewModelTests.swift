import Foundation
import MenuDateApplication
import MenuDateDomain
import MenuDatePreviewSupport
import Testing

@testable import MenuDatePresentation

struct LaunchFailure: Error {}

@MainActor
@Suite struct SettingsViewModelTests {
    @Test func 読み込むと各タブの現在の状態が入る() async {
        let harness = Harness()
        let settings = harness.settings
        await settings.load()

        #expect(settings.accounts == SampleData.accounts)
        #expect(settings.calendarsPhase == .loaded)
        #expect(settings.calendars.map(\.calendar.name) == ["プライベート", "日本の祝日", "仕事", "日本の祝日"])
        #expect(settings.calendars.allSatisfy { $0.isVisible })
        #expect(!settings.launchAtLogin)
    }

    // MARK: - 許可の状態

    @Test func 許可が未決定なら許可を求める案内を出して許可は求めない() async {
        let harness = Harness(status: .notDetermined)
        await harness.settings.load()

        #expect(harness.settings.calendarsPhase == .guide(.notDetermined))
        #expect(harness.settings.calendarSections.isEmpty)
        #expect(await harness.authorizer.requestCount == 0)
    }

    @Test func 許可が拒否されていればシステム設定を開く案内を出す() async {
        let harness = Harness(status: .denied)
        await harness.settings.load()
        #expect(harness.settings.calendarsPhase == .guide(.denied))
    }

    @Test func カレンダーがなければインターネットアカウントの案内を出す() async {
        let harness = Harness(accounts: [], calendars: [])
        await harness.settings.load()
        #expect(harness.settings.calendarsPhase == .guide(.noCalendars))
    }

    @Test func 許可のボタンで許可を求めると一覧が読み込まれ変更が通知される() async {
        let harness = Harness(status: .notDetermined)
        let settings = harness.settings
        await settings.load()
        let before = harness.popover.changeRevision

        await settings.perform(.notDetermined)

        #expect(await harness.authorizer.requestCount == 1)
        #expect(settings.calendarsPhase == .loaded)
        #expect(settings.calendars.count == 4)
        #expect(harness.popover.changeRevision > before)
        #expect(!settings.isRequestingAccess)
    }

    @Test func 許可を求める失敗はエラーの文にする() async {
        let harness = Harness(status: .notDetermined, requestError: CocoaError(.fileReadUnknown))
        let settings = harness.settings
        await settings.load()

        await settings.perform(.notDetermined)

        #expect(settings.calendarsPhase == .failed("予期しないエラーが発生しました。もう一度お試しください。"))
    }

    @Test func 拒否の案内のボタンはカレンダーのプライバシーの画面を開く() async {
        let harness = Harness(status: .denied)
        await harness.settings.perform(.denied)
        #expect(harness.settingsOpener.openedDestinations == [.calendarPrivacy])
    }

    @Test func インターネットアカウントを開く() async {
        let harness = Harness()
        harness.settings.openInternetAccounts()
        await harness.settings.perform(.noCalendars)
        #expect(harness.settingsOpener.openedDestinations == [.internetAccounts, .internetAccounts])
    }

    @Test func カレンダーの取得に失敗したらエラーの文を出す() async {
        let harness = Harness(accounts: [], calendars: [])
        let failing = SettingsViewModel(
            getLaunchAtLogin: GetLaunchAtLoginUseCase(service: harness.launchAtLogin),
            setLaunchAtLogin: SetLaunchAtLoginUseCase(service: harness.launchAtLogin),
            listCalendars: ListCalendarsUseCase(
                authorizer: harness.authorizer,
                calendarRepository: InMemoryCalendarRepository(error: CocoaError(.fileReadUnknown)),
                visibilityRepository: harness.visibility
            ),
            setCalendarVisibility: SetCalendarVisibilityUseCase(visibilityRepository: harness.visibility),
            requestCalendarAccess: RequestCalendarAccessUseCase(authorizer: harness.authorizer),
            openSystemSettings: OpenSystemSettingsUseCase(opener: harness.settingsOpener),
            changeNotifier: DataChangeNotifier(),
            notificationCenter: harness.notificationCenter
        )
        await failing.load()
        #expect(failing.calendarsPhase == .failed("予期しないエラーが発生しました。もう一度お試しください。"))
    }

    // MARK: - 他の画面での変更

    @Test func ポップオーバーで許可すると設定のカレンダー一覧が更新される() async {
        let harness = Harness(status: .notDetermined)
        let settings = harness.settings
        await settings.load()
        #expect(settings.calendarsPhase == .guide(.notDetermined))

        await harness.popover.perform(.notDetermined)
        #expect(settings.changeRevision != 0)
        await settings.refreshIfChangedElsewhere()

        #expect(settings.calendarsPhase == .loaded)
        #expect(settings.calendars.count == 4)
    }

    @Test func 自分で起こした変更では読み直さない() async {
        let harness = Harness()
        let settings = harness.settings
        await settings.load()
        await settings.setVisibility(of: SampleData.workCalendar.id, isVisible: false)
        let before = await harness.calendarRepository.callCount

        await settings.refreshIfChangedElsewhere()
        #expect(await harness.calendarRepository.callCount == before)
    }

    @Test func カレンダーのデータが変わった通知で一覧を読み直す() async {
        let harness = Harness()
        let settings = harness.settings
        await settings.load()
        let before = await harness.calendarRepository.callCount

        harness.notificationCenter.post(name: .calendarStoreDidChange, object: nil)
        var after = before
        for _ in 0..<1000 where after <= before {
            await Task.yield()
            after = await harness.calendarRepository.callCount
        }

        #expect(after > before)
    }

    // MARK: - 一般

    @Test func ログイン時の起動を切り替える() async {
        let harness = Harness()
        await harness.settings.setLaunchAtLogin(true)

        #expect(harness.settings.launchAtLogin)
        #expect(harness.settings.launchAtLoginError == nil)
        #expect(await harness.launchAtLogin.isEnabled())
    }

    @Test func ログイン時の起動の変更に失敗したらトグルを元に戻す() async {
        let harness = Harness(launchAtLoginError: LaunchFailure())
        await harness.settings.setLaunchAtLogin(true)

        #expect(!harness.settings.launchAtLogin)
        #expect(harness.settings.launchAtLoginError == "ログイン時の起動を変更できませんでした。")
    }

    // MARK: - カレンダー

    @Test func カレンダーの表示を切り替える() async {
        let harness = Harness()
        let settings = harness.settings
        await settings.load()

        await settings.setVisibility(of: SampleData.personalCalendar.id, isVisible: false)
        #expect(settings.calendars.map(\.isVisible) == [false, true, true, true])
        #expect(await harness.visibility.load().isVisible(SampleData.personalCalendar.id) == false)

        await settings.setVisibility(of: SampleData.personalCalendar.id, isVisible: true)
        #expect(settings.calendars.map(\.isVisible) == [true, true, true, true])
    }

    @Test func カレンダーをアカウント名を見出しにしたセクションに分ける() async {
        let harness = Harness()
        await harness.settings.load()
        let sections = harness.settings.calendarSections

        #expect(sections.map(\.title) == ["Google", "仕事"])
        #expect(sections[0].items.map(\.calendar.name) == ["プライベート", "日本の祝日"])
        #expect(sections[1].items.map(\.calendar.name) == ["仕事", "日本の祝日"])
    }

    @Test func カレンダーを持たないアカウントのセクションは作らない() async {
        let harness = Harness(accounts: SampleData.accounts, calendars: [SampleData.personalCalendar])
        await harness.settings.load()
        #expect(harness.settings.calendarSections.map(\.title) == ["Google"])
    }

    @Test func 同じ名前のカレンダーでも別のアカウントのカレンダーの表示は独立している() async {
        let harness = Harness()
        let settings = harness.settings
        await settings.load()

        await settings.setVisibility(of: SampleData.holidayCalendar.id, isVisible: false)

        let sections = settings.calendarSections
        #expect(sections[0].items.map(\.isVisible) == [true, false])
        #expect(sections[1].items.map(\.isVisible) == [true, true])
    }
}
