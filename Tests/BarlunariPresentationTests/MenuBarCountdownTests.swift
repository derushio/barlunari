import AppKit
import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

@MainActor
@Suite(.timeLimit(.minutes(1))) struct MenuBarCountdownTests {
    /// 現在は 2026-10-24 12:00。次の予定は 14:00 の「デザインレビュー」で、16:00 の会議は辞退している。
    func started(_ harness: Harness) async -> MenuBarCountdownViewModel {
        harness.countdown.start()
        await harness.countdown.waitForLoad()
        return harness.countdown
    }

    /// ポップオーバーの ViewModel と通知を分けた、専用の通知センターを購読する残り時間。ポップオーバーの取得が回数に混ざらない。
    func isolatedCountdown(
        _ harness: Harness, center: NotificationCenter = NotificationCenter(), workspace: NotificationCenter = NotificationCenter()
    ) -> MenuBarCountdownViewModel {
        MenuBarCountdownViewModel(
            loadUpcomingEvents: LoadUpcomingEventsUseCase(
                authorizer: harness.authorizer,
                calendarRepository: harness.calendarRepository,
                eventRepository: harness.eventRepository,
                visibilityRepository: harness.visibility,
                settingsRepository: harness.countdownSettings,
                calendarSettingsRepository: harness.countdownCalendarSettings,
                dateProvider: harness.overridingDateProvider
            ),
            dateProvider: harness.overridingDateProvider,
            changeNotifier: harness.notifier,
            workspaceNotificationCenter: workspace,
            notificationCenter: center
        )
    }

    func advance(_ harness: Harness, by seconds: TimeInterval) {
        harness.dateProvider.set(harness.dateProvider.now.addingTimeInterval(seconds))
        harness.countdown.recompute()
    }

    // MARK: - 表示

    @Test func 次の予定までの残り時間をゼロ埋めの時分で出す() async {
        let countdown = await started(Harness())
        #expect(countdown.displayText == "02:00")
        #expect(countdown.accessibilityLabel == "次の予定まで2時間")
    }

    @Test func 時間と分があるときのラベル() async {
        let harness = Harness()
        let countdown = await started(harness)
        advance(harness, by: 35 * 60)
        #expect(countdown.displayText == "01:25")
        #expect(countdown.accessibilityLabel == "次の予定まで1時間25分")
    }

    @Test func 一時間未満のラベルは分だけ() async {
        let harness = Harness()
        let countdown = await started(harness)
        advance(harness, by: 95 * 60)
        #expect(countdown.displayText == "00:25")
        #expect(countdown.accessibilityLabel == "次の予定まで25分")
    }

    @Test func 開始の直前でも00_00を出さない() async {
        let harness = Harness()
        let countdown = await started(harness)
        advance(harness, by: 2 * 3600 - 30)
        #expect(countdown.displayText == "00:01")
    }

    @Test func 予定が始まったら次の予定に切り替わり辞退した予定は飛ばす() async {
        let harness = Harness()
        let countdown = await started(harness)
        advance(harness, by: 2 * 3600)
        #expect(countdown.displayText == "05:00")
        #expect(countdown.accessibilityLabel == "次の予定まで5時間")
    }

    @Test func 対象の予定がなくなるとnilになる() async {
        let harness = Harness()
        let countdown = await started(harness)
        advance(harness, by: 7 * 3600)
        #expect(countdown.displayText == nil)
        #expect(countdown.accessibilityLabel == nil)
    }

    @Test func 二十四時間より先の予定は対象にしない() async {
        let harness = Harness(events: [SampleData.workEvent("先の予定", on: SampleData.day(2026, 10, 26), hour: 11)])
        let countdown = await started(harness)
        #expect(countdown.displayText == nil)
    }

    @Test func 許可がなければnilになる() async {
        let countdown = await started(Harness(status: .denied))
        #expect(countdown.displayText == nil)
        #expect(countdown.accessibilityLabel == nil)
    }

    @Test func 取得に失敗したらnilになる() async {
        struct Failure: Error {}
        let countdown = await started(Harness(eventError: Failure()))
        #expect(countdown.displayText == nil)
    }

    // MARK: - 取得し直し

    @Test func 取得した範囲の残りが二十四時間を切ったら取得し直す() async {
        let harness = Harness()
        let countdown = await started(harness)
        #expect(await harness.eventRepository.requests.count == 1)

        advance(harness, by: 3600)
        await countdown.waitForLoad()
        #expect(await harness.eventRepository.requests.count == 1)

        advance(harness, by: 24 * 3600)
        await countdown.waitForLoad()
        #expect(await harness.eventRepository.requests.count == 2)
        // 10 月 25 日 13:00。26 日 11:00 の予定が 22 時間先になる。
        #expect(countdown.displayText == "22:00")
    }

    @Test func 変更通知は進行中の取得を取り消さず終わってから一回だけ取得し直す() async throws {
        let harness = Harness()
        let center = NotificationCenter()
        let countdown = isolatedCountdown(harness, center: center)
        await harness.eventRepository.gate()
        countdown.start()
        await harness.eventRepository.waitForPending(1)

        for _ in 0..<3 { center.post(name: .calendarStoreDidChange, object: nil) }
        await yieldRepeatedly()
        #expect(await harness.eventRepository.requests.count == 1)

        await harness.eventRepository.resume(at: 0, events: SampleData.events)
        await harness.eventRepository.waitForPending(2)
        // 止めた取得がなければ、添字の外を再開してテストのプロセスごと落ちるため、先に確かめる。
        try #require(await harness.eventRepository.pendingCount == 2)
        await harness.eventRepository.resume(at: 1, events: SampleData.events)
        await countdown.waitForLoad()

        #expect(await harness.eventRepository.requests.count == 2)
        #expect(countdown.displayText == "02:00")
    }

    @Test(arguments: [Notification.Name.calendarStoreDidChange, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange])
    func 通知を受けると取得し直す(name: Notification.Name) async {
        let harness = Harness()
        let center = NotificationCenter()
        let countdown = isolatedCountdown(harness, center: center)
        countdown.start()
        await countdown.waitForLoad()

        center.post(name: name, object: nil)
        await harness.eventRepository.waitForRequests(2)
        await countdown.waitForLoad()

        #expect(await harness.eventRepository.requests.count == 2)
    }

    @Test func スリープからの復帰で取得し直す() async {
        let harness = Harness()
        let workspace = NotificationCenter()
        let countdown = isolatedCountdown(harness, workspace: workspace)
        countdown.start()
        await countdown.waitForLoad()

        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        await harness.eventRepository.waitForRequests(2)
        await countdown.waitForLoad()

        #expect(await harness.eventRepository.requests.count == 2)
    }

    @Test func 変更通知による取得ではサーバーとの同期を求めない() async {
        let harness = Harness()
        let center = NotificationCenter()
        let countdown = isolatedCountdown(harness, center: center)
        countdown.start()
        await countdown.waitForLoad()
        center.post(name: .calendarStoreDidChange, object: nil)
        await harness.eventRepository.waitForRequests(2)
        await countdown.waitForLoad()
        #expect(harness.sourceRefresher.refreshCount == 0)
    }

    @Test func startを二回呼んでも購読は一組だけ() async {
        let harness = Harness()
        _ = await started(harness)
        harness.countdown.start()
        await harness.countdown.waitForLoad()
        #expect(await harness.eventRepository.requests.count == 1)
    }

    @Test func カレンダーの表示切り替えの通知で取得し直す() async {
        let harness = Harness()
        _ = await started(harness)
        await harness.visibility.update { $0.hide(SampleData.workCalendar.id) }

        harness.notifier.notifyChange()
        await waitUntil { harness.countdown.displayText == "07:00" }
        await harness.countdown.waitForLoad()

        // 仕事のカレンダーを非表示にすると、次の予定は 19:00 の「夕食」になる。
        #expect(harness.countdown.displayText == "07:00")
    }

    // MARK: - 対象の設定

    @Test func 詳細で除外すると残り時間の対象から外れ戻すと対象に戻る() async throws {
        let harness = Harness()
        let countdown = await started(harness)
        let popover = await harness.loadedPopover()
        let row = try #require(popover.selectedSection.rows.first { $0.title == "デザインレビュー" })
        popover.showDetail(of: row)

        await popover.setIncludedInCountdown(false)
        await waitUntil { countdown.displayText == "07:00" }
        await countdown.waitForLoad()
        #expect(countdown.displayText == "07:00")

        await popover.setIncludedInCountdown(true)
        await waitUntil { countdown.displayText == "02:00" }
        await countdown.waitForLoad()
        #expect(countdown.displayText == "02:00")
    }

    @Test func 終日予定は詳細で対象にするとその日の0時までの残り時間になる() async throws {
        let harness = Harness(events: SampleData.events.filter { $0.title == "引っ越し" })
        let countdown = await started(harness)
        #expect(countdown.displayText == nil)

        let popover = await harness.loadedPopover()
        popover.select(SampleData.day(2026, 10, 25))
        let row = try #require(popover.selectedSection.rows.first { $0.title == "引っ越し" })
        popover.showDetail(of: row)
        await popover.setIncludedInCountdown(true)
        // 現在は 10/24 12:00。10/25 の 0:00 まで 12 時間。
        await waitUntil { countdown.displayText == "12:00" }
        await countdown.waitForLoad()
        #expect(countdown.displayText == "12:00")
    }

    @Test func 辞退した予定は詳細で対象にしても数えない() async throws {
        let harness = Harness(events: SampleData.events.filter { $0.title == "辞退した会議" })
        let countdown = await started(harness)
        let popover = await harness.loadedPopover()
        let row = try #require(popover.selectedSection.rows.first { $0.title == "辞退した会議" })
        popover.showDetail(of: row)
        await popover.setIncludedInCountdown(false)
        await popover.setIncludedInCountdown(true)
        await countdown.waitForLoad()
        #expect(popover.eventDetail?.includedInCountdown == true)
        #expect(countdown.displayText == nil)
    }
}
