import AppKit
import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

@MainActor
@Suite struct SourceRefreshTests {
    // MARK: - 同期を求めるきっかけ

    @Test func パネルを開くと同期を求める() async {
        let harness = Harness()
        let viewModel = harness.popover

        viewModel.popoverDidAppear()
        await waitUntil { harness.sourceRefresher.refreshCount == 1 }
        await viewModel.waitForLoad()

        #expect(harness.sourceRefresher.refreshCount == 1)
        #expect(viewModel.phase == .loaded)
    }

    @Test func 前回の読み込みが新しく読み直さない場合でも開くと同期を求める() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        viewModel.popoverDidAppear()
        await waitUntil { harness.sourceRefresher.refreshCount == 1 }
        await yieldRepeatedly()

        #expect(harness.sourceRefresher.refreshCount == 1)
        #expect(await harness.eventRepository.requests.count == before)
    }

    @Test func 更新ボタンの操作で同期を求めて読み直す() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        viewModel.refresh()
        await waitUntil { harness.sourceRefresher.refreshCount == 1 }
        await viewModel.waitForLoad()

        #expect(harness.sourceRefresher.refreshCount == 1)
        #expect(await harness.eventRepository.requests.count == before + 1)
    }

    @Test func 再読み込みだけの操作では同期を求めない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()

        viewModel.reload()
        await viewModel.waitForLoad()
        await yieldRepeatedly()

        #expect(harness.sourceRefresher.refreshCount == 0)
    }

    @Test func スリープからの復帰の通知で同期を求めて読み直す() async {
        let harness = Harness()
        _ = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        harness.workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitUntil { harness.sourceRefresher.refreshCount == 1 }
        var after = before
        while after == before {
            await Task.yield()
            after = await harness.eventRepository.requests.count
        }
        await harness.popover.waitForLoad()

        #expect(harness.sourceRefresher.refreshCount == 1)
        #expect(await harness.eventRepository.requests.count == before + 1)
    }

    @Test func 変更通知では読み直すだけで同期を求めない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        harness.notificationCenter.post(name: .calendarStoreDidChange, object: nil)
        var after = before
        while after == before {
            await Task.yield()
            after = await harness.eventRepository.requests.count
        }
        await viewModel.waitForLoad()
        await yieldRepeatedly()

        #expect(harness.sourceRefresher.refreshCount == 0)
    }

    // MARK: - 変更通知の読み直し

    @Test func 読み込み中に変更通知が5回届いても取得は2回で最後の結果が反映される() async {
        let harness = Harness(hiddenCalendars: [
            SampleData.personalCalendar, SampleData.holidayCalendar, SampleData.workAccountHolidayCalendar,
        ])
        await harness.eventRepository.gate()
        let viewModel = harness.popover

        viewModel.reload()
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }
        for _ in 0..<5 { harness.notificationCenter.post(name: .calendarStoreDidChange, object: nil) }
        await yieldRepeatedly(500)
        // 進行中の取得は取り消されず、新しい取得も始まらない。
        #expect(await harness.eventRepository.requests.count == 1)

        await harness.eventRepository.resume(at: 0, events: SampleData.events)
        while await harness.eventRepository.pendingCount < 2 { await Task.yield() }
        await yieldRepeatedly(500)
        #expect(await harness.eventRepository.requests.count == 2)

        await harness.eventRepository.resume(at: 1, events: [])
        await viewModel.waitForLoad()

        #expect(await harness.eventRepository.requests.count == 2)
        #expect(viewModel.phase == .loaded)
        #expect(viewModel.snapshot.days.allSatisfy { $0.events.isEmpty })
    }

    @Test func 読み込み中でなければ変更通知ですぐに読み直す() async {
        let harness = Harness()
        _ = await harness.loadedPopover()
        await harness.eventRepository.gate()

        harness.notificationCenter.post(name: .calendarStoreDidChange, object: nil)
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }

        #expect(await harness.eventRepository.pendingCount == 1)
        await harness.eventRepository.resume(at: 0, events: [])
        await harness.popover.waitForLoad()
    }

    @Test func 別の理由で新しい読み込みを始めたら通知の印は消える() async {
        let harness = Harness(hiddenCalendars: [
            SampleData.personalCalendar, SampleData.holidayCalendar, SampleData.workAccountHolidayCalendar,
        ])
        await harness.eventRepository.gate()
        let viewModel = harness.popover

        viewModel.reload()
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }
        harness.notificationCenter.post(name: .calendarStoreDidChange, object: nil)
        await yieldRepeatedly(500)
        viewModel.reload()
        while await harness.eventRepository.pendingCount < 2 { await Task.yield() }

        await harness.eventRepository.resume(at: 1, events: [])
        await viewModel.waitForLoad()
        // 取り消した最初の読み込みも返し、待ち続ける呼び出しを残さない。
        await harness.eventRepository.resume(at: 0, events: [])
        await yieldRepeatedly(500)

        // 通知の後に始めた読み込みが通知の分も含むので、さらに読み直さない。
        #expect(await harness.eventRepository.requests.count == 2)
    }
}
