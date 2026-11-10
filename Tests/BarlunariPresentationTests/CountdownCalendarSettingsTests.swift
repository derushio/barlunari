import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

/// カレンダーごとの残り時間の設定。設定画面の ViewModel、メニューバーの残り時間、ポップオーバーの記号と詳細を通して確かめる。
@MainActor
@Suite(.timeLimit(.minutes(1))) struct CountdownCalendarSettingsTests {
    let work = SampleData.workCalendar

    // MARK: - 設定画面

    @Test func 読み込むと保存済みの含めないカレンダーが入る() async {
        let harness = Harness(countdownExcludedCalendars: [work])
        await harness.settings.load()
        #expect(!harness.settings.isIncludedInCountdown(work.id))
        #expect(harness.settings.isIncludedInCountdown(SampleData.personalCalendar.id))
        #expect(harness.settings.countdownCalendarSettings.excludedCalendars == [work.id])
    }

    @Test func 含めないに切り替えると保存し変更を通知する() async {
        let harness = Harness()
        let settings = harness.settings
        await settings.load()

        await settings.setIncludedInCountdown(work.id, isIncluded: false)

        #expect(!settings.isIncludedInCountdown(work.id))
        #expect(settings.countdownError == nil)
        #expect(await harness.countdownCalendarSettings.load().excludedCalendars == [work.id])
        #expect(harness.notifier.revision == 1)

        await settings.setIncludedInCountdown(work.id, isIncluded: true)
        #expect(settings.isIncludedInCountdown(work.id))
        #expect(await harness.countdownCalendarSettings.load().excludedCalendars.isEmpty)
        #expect(harness.notifier.revision == 2)
    }

    @Test func 同じ名前のカレンダーでもアカウントごとに切り替える() async {
        let harness = Harness()
        await harness.settings.load()
        await harness.settings.setIncludedInCountdown(SampleData.holidayCalendar.id, isIncluded: false)
        #expect(!harness.settings.isIncludedInCountdown(SampleData.holidayCalendar.id))
        #expect(harness.settings.isIncludedInCountdown(SampleData.workAccountHolidayCalendar.id))
    }

    @Test func 保存に失敗したら表示を戻しエラーの文を出し通知しない() async {
        struct SaveFailure: Error {}
        let harness = Harness()
        let settings = harness.settings
        await settings.load()
        await harness.countdownCalendarSettings.setFailure(SaveFailure())

        await settings.setIncludedInCountdown(work.id, isIncluded: false)

        #expect(settings.isIncludedInCountdown(work.id))
        #expect(settings.countdownError == "予期しないエラーが発生しました。もう一度お試しください。")
        #expect(harness.notifier.revision == 0)
        #expect(await harness.countdownCalendarSettings.load() == CountdownCalendarSettings())
    }

    @Test func 失敗のあとの成功でエラーの文を消す() async {
        struct SaveFailure: Error {}
        let harness = Harness()
        await harness.settings.load()
        await harness.countdownCalendarSettings.setFailure(SaveFailure())
        await harness.settings.setIncludedInCountdown(work.id, isIncluded: false)
        await harness.countdownCalendarSettings.setFailure(nil)
        await harness.settings.setIncludedInCountdown(work.id, isIncluded: false)
        #expect(harness.settings.countdownError == nil)
        #expect(!harness.settings.isIncludedInCountdown(work.id))
    }

    @Test func 非表示のカレンダーの設定は表示に戻しても残る() async {
        let harness = Harness()
        let settings = harness.settings
        await settings.load()
        await settings.setIncludedInCountdown(work.id, isIncluded: false)
        await settings.setVisibility(of: work.id, isVisible: false)
        await settings.setVisibility(of: work.id, isVisible: true)
        #expect(!settings.isIncludedInCountdown(work.id))
    }

    @Test func カレンダーの設定を変えても予定ごとの選択は消えない() async throws {
        let harness = Harness()
        let popover = await harness.loadedPopover()
        let row = try #require(popover.selectedSection.rows.first { $0.title == "デザインレビュー" })
        popover.showDetail(of: row)
        await popover.setIncludedInCountdown(false)
        let chosen = await harness.countdownSettings.load()

        await harness.settings.load()
        await harness.settings.setIncludedInCountdown(work.id, isIncluded: false)
        await harness.settings.setIncludedInCountdown(work.id, isIncluded: true)

        #expect(await harness.countdownSettings.load() == chosen)
    }

    // MARK: - メニューバー

    @Test func カレンダーの設定を変えるとメニューバーの表示が変わる() async {
        // 現在は 12:00。仕事のカレンダーの次の予定は 14:00 の「デザインレビュー」、それ以外では 19:00 の「夕食」。
        let harness = Harness()
        harness.countdown.start()
        await harness.countdown.waitForLoad()
        #expect(harness.countdown.displayText == "02:00")
        await harness.settings.load()
        let before = await harness.eventRepository.requests.count

        await harness.settings.setIncludedInCountdown(work.id, isIncluded: false)
        await harness.eventRepository.waitForRequests(before + 1)
        await harness.countdown.waitForLoad()
        #expect(harness.countdown.displayText == "07:00")

        await harness.settings.setIncludedInCountdown(work.id, isIncluded: true)
        await harness.eventRepository.waitForRequests(before + 2)
        await harness.countdown.waitForLoad()
        #expect(harness.countdown.displayText == "02:00")
    }

    @Test func 起動時から含めないカレンダーの予定は数えない() async {
        let harness = Harness(countdownExcludedCalendars: [work])
        harness.countdown.start()
        await harness.countdown.waitForLoad()
        #expect(harness.countdown.displayText == "07:00")
    }

    // MARK: - ポップオーバー

    @Test func 含めないカレンダーの予定は詳細のチェックがオフで説明の印が付き記号は付かない() async throws {
        let harness = Harness(countdownExcludedCalendars: [work])
        let popover = await harness.loadedPopover()
        let row = try #require(popover.selectedSection.rows.first { $0.title == "デザインレビュー" })
        #expect(row.countdownMark == .none)

        popover.showDetail(of: row)
        #expect(popover.eventDetail?.includedInCountdown == false)
        #expect(popover.eventDetail?.isCalendarExcludedFromCountdown == true)

        let dinner = try #require(popover.selectedSection.rows.first { $0.title == "夕食" })
        popover.showDetail(of: dinner)
        #expect(popover.eventDetail?.includedInCountdown == true)
        #expect(popover.eventDetail?.isCalendarExcludedFromCountdown == false)
    }

    @Test func 設定画面での変更をポップオーバーが読み直し予定ごとの選択が優先される() async throws {
        let harness = Harness()
        harness.countdown.start()
        await harness.countdown.waitForLoad()
        let popover = await harness.loadedPopover()
        let row = try #require(popover.selectedSection.rows.first { $0.title == "デザインレビュー" })
        popover.showDetail(of: row)
        #expect(popover.eventDetail?.includedInCountdown == true)
        await harness.settings.load()
        let before = await harness.eventRepository.requests.count

        // 設定画面で仕事のカレンダーを外す。ポップオーバーは変更の通知を受けて読み直す。
        await harness.settings.setIncludedInCountdown(work.id, isIncluded: false)
        popover.reloadIfChangedElsewhere()
        await popover.waitForLoad()
        await harness.eventRepository.waitForRequests(before + 2)
        await harness.countdown.waitForLoad()

        #expect(popover.eventDetail?.includedInCountdown == false)
        #expect(popover.eventDetail?.isCalendarExcludedFromCountdown == true)
        #expect(popover.selectedSection.rows.first { $0.title == "デザインレビュー" }?.countdownMark == CountdownMark.none)
        #expect(harness.countdown.displayText == "07:00")

        // 詳細でチェックすると、この予定だけ含める選択になる。カレンダーの設定は変わらない。
        await popover.setIncludedInCountdown(true)
        await harness.eventRepository.waitForRequests(before + 3)
        await harness.countdown.waitForLoad()
        #expect(popover.eventDetail?.includedInCountdown == true)
        #expect(popover.eventDetail?.isCalendarExcludedFromCountdown == true)
        #expect(popover.selectedSection.rows.first { $0.title == "デザインレビュー" }?.countdownMark == .included)
        #expect(await harness.countdownCalendarSettings.load().excludedCalendars == [work.id])
        #expect(harness.countdown.displayText == "02:00")
    }
}
