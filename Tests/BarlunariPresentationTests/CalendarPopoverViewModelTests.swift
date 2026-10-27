import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

@MainActor
@Suite struct CalendarPopoverViewModelTests {
    // MARK: - 読み込み済みの表示

    @Test func 読み込むと今日の前後に連続した予定一覧が日ごとの見出し付きで並ぶ() async throws {
        let viewModel = await Harness().loadedPopover()

        #expect(viewModel.phase == .loaded)
        let today = SampleData.today
        let sections = viewModel.sections(from: today, count: 3)
        #expect(sections.map(\.day) == [today, SampleData.day(2026, 10, 25), SampleData.day(2026, 10, 26)])
        #expect(sections[0].title == "10月24日(土)")
        #expect(sections[0].relativeLabel == "今日")
        #expect(sections[1].title == "10月25日(日)")
        #expect(sections[1].relativeLabel == "明日")
        #expect(sections[2].relativeLabel == nil)
        #expect(sections[0].rows.map(\.title) == ["朝会", "デザインレビュー", "夕食"])
        #expect(sections[1].rows.map(\.timeText) == ["終日"])
    }

    @Test func 日を番号で引くと範囲の最初の日から連続した日になる() {
        let viewModel = Harness().popover
        let range = viewModel.agendaRange

        #expect(viewModel.agendaDay(at: 0) == range.start)
        #expect(viewModel.agendaDay(at: 1) == range.start.adding(days: 1, calendar: SampleData.calendar))
        #expect(viewModel.agendaIndex(of: SampleData.today).flatMap(viewModel.agendaDay(at:)) == SampleData.today)
        #expect(viewModel.agendaDay(at: viewModel.agendaDayCount) == nil)
        #expect(viewModel.agendaSection(at: -1) == nil)
        #expect(viewModel.agendaSection(at: viewModel.agendaDayCount) == nil)
        #expect(viewModel.agendaIndex(of: SampleData.day(2040, 1, 1)) == nil)
    }

    @Test func 行は時刻と場所と色を持ち終わった予定は過去として扱う() async {
        let viewModel = await Harness().loadedPopover()
        let rows = viewModel.selectedSection.rows

        #expect(rows[0].timeText == "10:00〜10:15")
        #expect(rows[0].isPast)
        #expect(!rows[1].isPast)
        #expect(rows[1].location == "会議室 A")
        #expect(rows[1].color == SampleData.workCalendar.color)
        #expect(rows[2].color == SampleData.personalCalendar.color)
    }

    @Test func 日をまたぐ予定はその日に収まる側の時刻だけを出す() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.select(SampleData.day(2026, 10, 29))
        await viewModel.waitForLoad()
        let sections = viewModel.sections(from: viewModel.selectedDay, count: 2)

        #expect(sections[0].rows.last?.timeText == "23:00〜")
        #expect(sections[1].rows.first?.timeText == "〜6:30")
    }

    @Test func カレンダー一覧を別に取得せず色は予定の取得結果から引く() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()

        // カレンダー一覧の取得は、予定の読み込みが呼ぶ `LoadAgendaUseCase` の内側で 1 回だけ行う。
        #expect(await harness.calendarRepository.callCount == 1)
        #expect(viewModel.selectedSection.rows.map(\.color) == [
            SampleData.workCalendar.color, SampleData.workCalendar.color, SampleData.personalCalendar.color,
        ])
    }

    @Test func タイトルが空なら代わりの文言を出す() async throws {
        let untitled = CalendarEvent(
            accountID: SampleData.workCalendar.accountID, id: try EventID("untitled"), calendarID: SampleData.workCalendar.calendarID, title: "",
            schedule: .timed(DateInterval(start: SampleData.date(2026, 10, 24, 15, 0), end: SampleData.date(2026, 10, 24, 16, 0)))
        )
        let viewModel = await Harness(events: [untitled]).loadedPopover()
        #expect(viewModel.selectedSection.rows.map(\.title) == ["(タイトルなし)"])
    }

    @Test func 予定がない日は行を持たない() async {
        let viewModel = await Harness(events: []).loadedPopover()
        #expect(viewModel.allSections.allSatisfy { $0.rows.isEmpty })
    }

    @Test func 最初の読み込みを終えるまでは読み込み中の表示にする() async {
        let harness = Harness()
        #expect(harness.popover.isAwaitingFirstLoad)

        let viewModel = await harness.loadedPopover()
        #expect(!viewModel.isAwaitingFirstLoad)
    }

    @Test func 最終更新時刻を出す() async {
        let viewModel = await Harness().loadedPopover()
        #expect(viewModel.lastUpdatedText == "最終更新 12:00")
    }

    // MARK: - 月のマス目

    @Test func マス目は6週で日曜は赤系と土曜は青系の区別を持つ() async {
        let viewModel = await Harness().loadedPopover()
        let weeks = viewModel.weeks

        #expect(weeks.count == 6)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(viewModel.weekdaySymbols == ["日", "月", "火", "水", "木", "金", "土"])
        #expect(weeks[0].map(\.weekdayKind) == [.sunday] + Array(repeating: .weekday, count: 5) + [.saturday])
        #expect(viewModel.monthTitle == "2026年10月")
    }

    @Test func 週の開始曜日はCalendarに従う() async {
        var calendar = SampleData.calendar
        calendar.firstWeekday = 2
        let viewModel = await Harness(dateProvider: MutableDateProvider(calendar: calendar)).loadedPopover()

        #expect(viewModel.weekdaySymbols == ["月", "火", "水", "木", "金", "土", "日"])
        #expect(viewModel.weeks[0].map(\.weekdayKind).last == .sunday)
    }

    @Test func 起動中に週の開始曜日を変えると見出しがマス目に追従する() async {
        let dateProvider = MutableDateProvider()
        let viewModel = await Harness(dateProvider: dateProvider).loadedPopover()
        #expect(viewModel.weekdaySymbols == ["日", "月", "火", "水", "木", "金", "土"])

        var calendar = SampleData.calendar
        calendar.firstWeekday = 2
        dateProvider.set(calendar: calendar)

        #expect(viewModel.weekdaySymbols == ["月", "火", "水", "木", "金", "土", "日"])
        #expect(viewModel.weeks[0].first?.weekdayKind == .weekday)
        #expect(viewModel.weeks[0].last?.weekdayKind == .sunday)
    }

    @Test func 今日と選択日と当月以外を区別しドットは最大3色にする() async {
        let viewModel = await Harness().loadedPopover()
        let cells = viewModel.weeks.flatMap { $0 }
        let today = cells.first { $0.day == SampleData.today }

        #expect(today?.isToday == true)
        #expect(today?.isSelected == true)
        #expect(today?.dotColors == [SampleData.workCalendar.color, SampleData.personalCalendar.color])
        #expect(cells.filter(\.isToday).count == 1)
        #expect(cells.first { $0.day == SampleData.day(2026, 9, 27) }?.isInMonth == false)
        #expect(cells.allSatisfy { $0.dotColors.count <= 3 })
    }

    // MARK: - 月の移動と選択

    @Test func 翌月と前月へ移動すると月の初日を選び読み込み直す() async {
        let viewModel = await Harness().loadedPopover()

        viewModel.showNextMonth()
        await viewModel.waitForLoad()
        #expect(viewModel.displayedMonth == SampleData.day(2026, 11, 1).calendarMonth)
        #expect(viewModel.selectedDay == SampleData.day(2026, 11, 1))
        #expect(viewModel.monthTitle == "2026年11月")
        #expect(viewModel.phase == .loaded)

        viewModel.showPreviousMonth()
        viewModel.showPreviousMonth()
        await viewModel.waitForLoad()
        #expect(viewModel.monthTitle == "2026年9月")
        #expect(viewModel.selectedDay == SampleData.day(2026, 9, 1))
    }

    @Test func 今日へ戻ると今日を含む月で今日を選ぶ() async {
        let viewModel = await Harness().loadedPopover()
        viewModel.showNextMonth()
        await viewModel.waitForLoad()

        viewModel.showToday()
        await viewModel.waitForLoad()
        #expect(viewModel.displayedMonth == SampleData.today.calendarMonth)
        #expect(viewModel.selectedDay == SampleData.today)
    }

    @Test func 当月以外の日を選ぶとその月へ移動して選択する() async {
        let viewModel = await Harness().loadedPopover()

        viewModel.select(SampleData.day(2026, 11, 3))
        await viewModel.waitForLoad()
        #expect(viewModel.monthTitle == "2026年11月")
        #expect(viewModel.selectedDay == SampleData.day(2026, 11, 3))
        #expect(viewModel.selectedSection.rows.map(\.title) == ["文化の日"])
    }

    @Test func 読み込み済みの範囲に収まる日の選択では読み込み直さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        viewModel.select(SampleData.day(2026, 10, 26))
        await viewModel.waitForLoad()
        let after = await harness.eventRepository.requests.count

        #expect(viewModel.selectedDay == SampleData.day(2026, 10, 26))
        #expect(after == before)
        #expect(viewModel.selectedSection.rows.map(\.title) == ["1on1"])
    }

    // MARK: - 取得範囲

    @Test func 取得範囲は表示できる全範囲で一度の読み込みで取得する() async throws {
        let harness = Harness()
        let viewModel = harness.popover
        viewModel.select(SampleData.day(2026, 8, 31))
        await viewModel.waitForLoad()

        let range = viewModel.fetchRange
        let timeline = try WeekTimeline(today: SampleData.today, firstWeekday: SampleData.calendar.firstWeekday)
        #expect(range == timeline.selectableDayRange)
        #expect(range == viewModel.agendaRange)
        let requests = await harness.eventRepository.requests
        // 表示するすべてのカレンダーを、1 回の取得で全範囲について取得する。
        #expect(requests == [range.dateInterval(calendar: SampleData.calendar)])
        #expect(await harness.eventRepository.requestedCalendars == [Set(SampleData.calendars.map(\.id))])
    }

    @Test func 取得範囲は選択日や表示月によらず同じ() async {
        let viewModel = await Harness().loadedPopover()
        let range = viewModel.fetchRange

        viewModel.showNextMonth()
        #expect(viewModel.fetchRange == range)
        viewModel.select(SampleData.day(2027, 3, 3))
        #expect(viewModel.fetchRange == range)
        viewModel.showToday()
        #expect(viewModel.fetchRange == range)
    }

    // MARK: - 古い読み込み

    @Test func 古い読み込みの結果は新しい結果を上書きしない() async {
        let harness = Harness(hiddenCalendars: [
            SampleData.personalCalendar, SampleData.holidayCalendar, SampleData.workAccountHolidayCalendar,
        ])
        await harness.eventRepository.gate()
        let viewModel = harness.popover

        viewModel.reload()
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }
        viewModel.showNextMonth()
        // 月の移動では読み込みは始まらない。明示の再読み込みで 2 つ目の読み込みを始める。
        viewModel.reload()
        while await harness.eventRepository.pendingCount < 2 { await Task.yield() }

        await harness.eventRepository.resume(at: 1, events: [])
        await viewModel.waitForLoad()
        #expect(viewModel.phase == .loaded)

        // 最初の読み込みが後から返っても、反映されない。
        await harness.eventRepository.resume(at: 0, events: SampleData.events)
        await yieldRepeatedly()

        #expect(viewModel.displayedMonth == SampleData.day(2026, 11, 1).calendarMonth)
        #expect(viewModel.snapshot.days.allSatisfy { $0.events.isEmpty })
        #expect(viewModel.phase == .loaded)
    }

    @Test func 読み込み前の日は読み込み中として扱い読み込み後に全範囲を予定なしにする() async {
        let harness = Harness(hiddenCalendars: [
            SampleData.personalCalendar, SampleData.holidayCalendar, SampleData.workAccountHolidayCalendar,
        ])
        await harness.eventRepository.gate()
        let viewModel = harness.popover
        let target = SampleData.day(2027, 3, 3)

        viewModel.reload()
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }
        #expect(viewModel.agendaDayCount == viewModel.agendaRange.days(calendar: SampleData.calendar).count)
        #expect(viewModel.sections(from: target, count: 30).allSatisfy { !$0.isLoaded && $0.rows.isEmpty })

        await harness.eventRepository.resume(at: 0, events: [])
        await viewModel.waitForLoad()
        #expect(viewModel.sections(from: target, count: 30).allSatisfy { $0.isLoaded && $0.rows.isEmpty })
        #expect(viewModel.section(of: viewModel.agendaRange.start).isLoaded)
        #expect(viewModel.section(of: viewModel.agendaRange.end.adding(days: -1, calendar: SampleData.calendar)).isLoaded)
    }

    // MARK: - 許可の状態

    @Test func 許可が未決定なら許可を求める案内の表示にして許可は求めない() async {
        let harness = Harness(status: .notDetermined)
        let viewModel = await harness.loadedPopover()
        #expect(viewModel.phase == .guide(.notDetermined))
        #expect(viewModel.allSections.allSatisfy { $0.rows.isEmpty })
        #expect(await harness.authorizer.requestCount == 0)
    }

    @Test func 許可が拒否されていればシステム設定を開く案内の表示にする() async {
        let viewModel = await Harness(status: .denied).loadedPopover()
        #expect(viewModel.phase == .guide(.denied))
    }

    @Test func カレンダーがなければインターネットアカウントの案内の表示にする() async {
        let viewModel = await Harness(accounts: [], calendars: []).loadedPopover()
        #expect(viewModel.phase == .guide(.noCalendars))
        #expect(viewModel.snapshot == .empty)
    }

    @Test func 許可のボタンで許可を求め許可されたら読み込み直す() async {
        let harness = Harness(status: .notDetermined, statusAfterRequest: .fullAccess)
        let viewModel = await harness.loadedPopover()

        await viewModel.perform(.notDetermined)
        await viewModel.waitForLoad()

        #expect(await harness.authorizer.requestCount == 1)
        #expect(viewModel.phase == .loaded)
        #expect(viewModel.selectedSection.rows.map(\.title) == ["朝会", "デザインレビュー", "夕食"])
    }

    @Test func 許可のボタンで拒否されたらシステム設定を開く案内にする() async {
        let harness = Harness(status: .notDetermined, statusAfterRequest: .denied)
        let viewModel = await harness.loadedPopover()

        await viewModel.perform(.notDetermined)
        await viewModel.waitForLoad()

        #expect(viewModel.phase == .guide(.denied))
    }

    @Test func 許可を求める失敗はエラーの文にする() async {
        let harness = Harness(status: .notDetermined, requestError: CocoaError(.fileReadUnknown))
        let viewModel = await harness.loadedPopover()

        await viewModel.perform(.notDetermined)

        #expect(viewModel.phase == .failed("予期しないエラーが発生しました。もう一度お試しください。"))
        #expect(!viewModel.isRequestingAccess)
    }

    @Test func 許可の結果を設定画面にも伝える() async {
        let harness = Harness(status: .notDetermined)
        let viewModel = await harness.loadedPopover()
        let before = harness.settings.changeRevision

        await viewModel.perform(.notDetermined)

        #expect(harness.settings.changeRevision > before)
        await harness.settings.refreshIfChangedElsewhere()
        #expect(harness.settings.calendarsPhase == .loaded)
    }

    @Test func 拒否の案内のボタンはカレンダーのプライバシーの画面を開く() async {
        let harness = Harness(status: .denied)
        let viewModel = await harness.loadedPopover()

        await viewModel.perform(.denied)

        #expect(harness.settingsOpener.openedDestinations == [.calendarPrivacy])
        #expect(await harness.authorizer.requestCount == 0)
    }

    @Test func カレンダーがない案内のボタンはインターネットアカウントを開く() async {
        let harness = Harness(accounts: [], calendars: [])
        let viewModel = await harness.loadedPopover()

        await viewModel.perform(.noCalendars)

        #expect(harness.settingsOpener.openedDestinations == [.internetAccounts])
    }

    @Test func 取得の失敗は再試行できるエラーの文にする() async {
        let viewModel = await Harness(eventError: CocoaError(.fileReadUnknown)).loadedPopover()
        #expect(viewModel.phase == .failed("予期しないエラーが発生しました。もう一度お試しください。"))
    }

    @Test func カレンダーのデータが変わった通知で読み直す() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        harness.notificationCenter.post(name: .calendarStoreDidChange, object: nil)
        var after = before
        for _ in 0..<1000 where after <= before {
            await Task.yield()
            after = await harness.eventRepository.requests.count
        }
        await viewModel.waitForLoad()

        #expect(after > before)
        #expect(viewModel.phase == .loaded)
    }

    // MARK: - URL を開く

    @Test func 参加ボタンは会議のURLを開く() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let standup = try #require(viewModel.selectedSection.rows.first)

        viewModel.openMeeting(of: standup)
        #expect(harness.opener.openedURLs == [
            URL(string: "https://meet.google.com/abc-defg-hij")!,
        ])
    }

    @Test func 会議のURLがない予定では参加しても何も開かない() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let dinner = try #require(viewModel.selectedSection.rows.last)

        #expect(!dinner.hasMeetingURL)
        viewModel.openMeeting(of: dinner)
        #expect(harness.opener.openedURLs.isEmpty)
    }

    // MARK: - ポップオーバーを開いたとき

    @Test func 読み込み中に開き直しても進行中の読み込みを取り消さない() async {
        let harness = Harness(hiddenCalendars: [
            SampleData.personalCalendar, SampleData.holidayCalendar, SampleData.workAccountHolidayCalendar,
        ])
        await harness.eventRepository.gate()
        let viewModel = harness.popover

        viewModel.popoverDidAppear()
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }
        viewModel.popoverDidAppear()
        viewModel.popoverDidAppear()
        await yieldRepeatedly()
        #expect(await harness.eventRepository.pendingCount == 1)

        await harness.eventRepository.resume(at: 0, events: SampleData.events)
        await viewModel.waitForLoad()
        #expect(viewModel.phase == .loaded)
        #expect(await harness.eventRepository.requests.count == 1)
    }

    @Test func ポップオーバー自身のウインドウが_keyになったときだけ開いたとみなす() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        harness.dateProvider.set(SampleData.now.addingTimeInterval(CalendarPopoverViewModel.staleInterval + 1))
        let before = await harness.eventRepository.requests.count

        let popoverWindow = NSObject()
        let settingsWindow = NSObject()
        viewModel.popoverWindowDidChange(ObjectIdentifier(popoverWindow), isKey: false)

        viewModel.windowDidBecomeKey(ObjectIdentifier(settingsWindow))
        await viewModel.waitForLoad()
        #expect(await harness.eventRepository.requests.count == before)

        viewModel.windowDidBecomeKey(ObjectIdentifier(popoverWindow))
        await viewModel.waitForLoad()
        #expect(await harness.eventRepository.requests.count > before)
    }

    @Test func ウインドウから外れたあとは_keyの通知に反応しない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        harness.dateProvider.set(SampleData.now.addingTimeInterval(CalendarPopoverViewModel.staleInterval + 1))
        let before = await harness.eventRepository.requests.count

        let window = NSObject()
        viewModel.popoverWindowDidChange(ObjectIdentifier(window), isKey: false)
        viewModel.popoverWindowDidChange(nil, isKey: false)
        viewModel.windowDidBecomeKey(ObjectIdentifier(window))
        await viewModel.waitForLoad()

        #expect(await harness.eventRepository.requests.count == before)
    }

    // MARK: - 日付の変化

    @Test func 日付が変わった後にポップオーバーを開くと選択日と表示月を今日に戻す() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.showNextMonth()
        await viewModel.waitForLoad()
        #expect(viewModel.selectedDay == SampleData.day(2026, 11, 1))

        harness.dateProvider.set(SampleData.date(2026, 10, 25, 9, 0))
        viewModel.popoverDidAppear()
        await viewModel.waitForLoad()

        #expect(viewModel.selectedDay == SampleData.day(2026, 10, 25))
        #expect(viewModel.displayedMonth == SampleData.day(2026, 10, 25).calendarMonth)
        #expect(viewModel.today == SampleData.day(2026, 10, 25))
        #expect(viewModel.selectedSection.relativeLabel == "今日")
        #expect(viewModel.phase == .loaded)
    }

    @Test func 日付が変わっていなければ開いても利用者の選択を保つ() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.select(SampleData.day(2026, 10, 26))

        harness.dateProvider.set(SampleData.now.addingTimeInterval(3 * 60 * 60))
        viewModel.popoverDidAppear()
        await viewModel.waitForLoad()

        #expect(viewModel.selectedDay == SampleData.day(2026, 10, 26))
    }

    @Test func 日付変更の通知で選択日と表示月を今日に戻して読み込み直す() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.showNextMonth()
        await viewModel.waitForLoad()
        let before = await harness.eventRepository.requests.count

        harness.dateProvider.set(SampleData.date(2026, 10, 25, 0, 0))
        harness.notificationCenter.post(name: .NSCalendarDayChanged, object: nil)
        await waitUntil { viewModel.selectedDay == SampleData.day(2026, 10, 25) }
        await viewModel.waitForLoad()

        #expect(viewModel.selectedDay == SampleData.day(2026, 10, 25))
        #expect(viewModel.displayedMonth == SampleData.day(2026, 10, 25).calendarMonth)
        #expect(await harness.eventRepository.requests.count > before)
    }

    @Test func タイムゾーンの変更の通知で今日を求め直して読み込み直す() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        // 2026-10-24 12:00 JST は、ホノルルでは 10/23 17:00 である。
        var calendar = SampleData.calendar
        calendar.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        harness.dateProvider.set(calendar: calendar)
        harness.notificationCenter.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await waitUntil { viewModel.today == SampleData.day(2026, 10, 23) && viewModel.selectedDay == viewModel.today }
        await viewModel.waitForLoad()

        #expect(viewModel.selectedDay == SampleData.day(2026, 10, 23))
        #expect(viewModel.selectedSection.relativeLabel == "今日")
        #expect(await harness.eventRepository.requests.count > before)
    }

    // MARK: - 設定との連携

    @Test func 設定での変更はポップオーバーの変更通知に伝わる() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        await harness.settings.load()
        let before = viewModel.changeRevision

        await harness.settings.setVisibility(of: SampleData.workCalendar.id, isVisible: false)
        #expect(viewModel.changeRevision > before)

        viewModel.reload()
        await viewModel.waitForLoad()
        #expect(viewModel.selectedSection.rows.map(\.title) == ["夕食"])
    }

    @Test func 古くない読み込み済みの状態では再表示しても読み込み直さない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let before = await harness.eventRepository.requests.count

        viewModel.popoverDidAppear()
        await viewModel.waitForLoad()
        #expect(await harness.eventRepository.requests.count == before)

        harness.dateProvider.set(SampleData.now.addingTimeInterval(CalendarPopoverViewModel.staleInterval + 1))
        viewModel.popoverDidAppear()
        await viewModel.waitForLoad()
        #expect(await harness.eventRepository.requests.count > before)
    }
}
