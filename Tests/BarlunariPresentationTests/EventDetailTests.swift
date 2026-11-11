import Foundation
import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

@MainActor
@Suite struct EventDetailViewModelTests {
    /// 2026-10-24 の「デザインレビュー」。場所、会議の URL、詳細の URL、メモ、参加者をすべて持つ。
    func designReview(_ viewModel: CalendarPopoverViewModel) throws -> AgendaRowState {
        try #require(viewModel.selectedSection.rows.first { $0.title == "デザインレビュー" })
    }

    func dinner(_ viewModel: CalendarPopoverViewModel) throws -> AgendaRowState {
        try #require(viewModel.selectedSection.rows.first { $0.title == "夕食" })
    }

    // MARK: - 開く

    @Test func 行を選ぶと詳細を表示する() async throws {
        let viewModel = await Harness().loadedPopover()
        #expect(viewModel.eventDetail == nil)

        let row = try designReview(viewModel)
        viewModel.showDetail(of: row)

        #expect(viewModel.detailEventID == row.id)
        #expect(viewModel.eventDetail?.id == row.id)
    }

    @Test func 詳細を開いても月と選択日は変わらない() async throws {
        let viewModel = await Harness().loadedPopover()
        let month = viewModel.displayedMonth
        let day = viewModel.selectedDay

        viewModel.showDetail(of: try designReview(viewModel))

        #expect(viewModel.displayedMonth == month)
        #expect(viewModel.selectedDay == day)
        #expect(viewModel.weeks.count == 6)
    }

    @Test func すべての項目がある予定の詳細() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))
        let detail = try #require(viewModel.eventDetail)

        #expect(detail.title == "デザインレビュー")
        #expect(detail.dateText == "10月24日(土) 14:00〜15:30")
        #expect(detail.color == SampleData.workCalendar.color)
        #expect(detail.calendarName == "仕事")
        #expect(detail.accountName == "仕事")
        #expect(detail.calendarText == "仕事")
        #expect(detail.location == "会議室 A")
        #expect(detail.meetingURL == URL(string: "https://meet.google.com/xyz-uvwx-rst"))
        #expect(detail.detailURL == URL(string: "https://example.com/events/design-review"))
        #expect(detail.attendanceText == "承諾")
        #expect(detail.participants.map(\.displayName) == [
            "山田 太郎", "佐藤 花子", "鈴木 一郎", "tanaka@example.com", "高橋 美咲", "伊藤 健",
        ])
        #expect(detail.notes != nil)
    }

    @Test func 値がない項目は持たない() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try dinner(viewModel))
        let detail = try #require(viewModel.eventDetail)

        #expect(detail.title == "夕食")
        #expect(detail.location == "渋谷")
        #expect(detail.meetingURL == nil)
        #expect(detail.detailURL == URL(string: "https://example.com/events/dinner"))
        #expect(detail.notes == nil)
        #expect(detail.participants.isEmpty)
        #expect(detail.calendarText == "プライベート（Google）")
    }

    @Test func 出欠の概念がない予定は出欠を持たない() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.select(SampleData.day(2026, 10, 25))
        await viewModel.waitForLoad()
        let row = try #require(viewModel.selectedSection.rows.first)

        viewModel.showDetail(of: row)

        #expect(viewModel.eventDetail?.title == "引っ越し")
        #expect(viewModel.eventDetail?.attendanceText == nil)
        #expect(viewModel.eventDetail?.dateText == "10月25日(日) 終日")
    }

    @Test(arguments: [
        (AttendanceStatus.accepted, "承諾"), (.tentative, "未定"), (.needsAction, "未回答"), (.declined, "辞退"),
    ])
    func 出欠を日本語にする(status: AttendanceStatus, expected: String) {
        #expect(status.displayText == expected)
    }

    @Test func 出欠の概念がなければ出欠の文を持たない() {
        #expect(AttendanceStatus.notApplicable.displayText == nil)
    }

    @Test func 参加者の行は名前とメールアドレスと主催者と自分と出欠を持つ() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))
        let participants = try #require(viewModel.eventDetail?.participants)

        let organizer = participants[0]
        #expect(organizer.displayName == "山田 太郎")
        #expect(organizer.emailAddress == "yamada@example.com")
        #expect(organizer.isOrganizer && !organizer.isCurrentUser)
        #expect(organizer.attendanceText == "承諾")
        #expect(organizer.accessibilityLabel == "山田 太郎、主催者、承諾")

        let me = participants[1]
        #expect(me.isCurrentUser && !me.isOrganizer)
        #expect(me.accessibilityLabel == "佐藤 花子、自分、承諾")

        // 名前がなければメールアドレスを表示名にし、メールアドレスを重ねて出さない。
        let emailOnly = participants[3]
        #expect(emailOnly.displayName == "tanaka@example.com")
        #expect(emailOnly.emailAddress == nil)
        #expect(emailOnly.attendanceText == "未回答")

        // 出欠の概念がない参加者は、出欠を出さない。
        #expect(participants[5].attendanceText == nil)
        #expect(participants[5].emailAddress == nil)
    }

    @Test func メモのURLをリンクにする() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))
        let notes = try #require(viewModel.eventDetail?.notes)

        let links = notes.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.com/docs/design-review-2026-10")!])
    }

    @Test func 一覧にない行では詳細を開かない() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let row = try designReview(viewModel)
        // 読み込み直した取得結果から、予定がなくなる。
        await harness.eventRepository.gate()
        viewModel.reload()
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }
        await harness.eventRepository.resume(at: 0, events: [])
        await viewModel.waitForLoad()

        viewModel.showDetail(of: row)

        #expect(viewModel.detailEventID == nil)
    }

    // MARK: - 一覧に戻る

    @Test func 戻るボタンで一覧に戻る() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))

        viewModel.closeDetail()

        #expect(viewModel.eventDetail == nil)
        #expect(viewModel.detailEventID == nil)
    }

    @Test func 日を選ぶと一覧に戻る() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))

        viewModel.select(SampleData.day(2026, 10, 27))

        #expect(viewModel.eventDetail == nil)
    }

    @Test func 同じ日を選び直しても一覧に戻る() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))

        viewModel.select(viewModel.selectedDay)

        #expect(viewModel.eventDetail == nil)
    }

    @Test func 月を移動すると一覧に戻る() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))
        viewModel.showNextMonth()
        #expect(viewModel.eventDetail == nil)

        await viewModel.waitForLoad()
        viewModel.showDetail(of: try #require(viewModel.section(of: SampleData.today).rows.first))
        viewModel.showPreviousMonth()
        #expect(viewModel.eventDetail == nil)
    }

    @Test func 今日を押すと一覧に戻る() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))

        viewModel.showToday()

        #expect(viewModel.eventDetail == nil)
    }

    @Test func ポップオーバーを開き直すと一覧に戻る() async throws {
        let viewModel = await Harness().loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))

        viewModel.popoverDidAppear()

        #expect(viewModel.eventDetail == nil)
    }

    @Test func ポップオーバーのウインドウが開き直されると一覧に戻る() async throws {
        let viewModel = await Harness().loadedPopover()
        let window = ObjectIdentifier(NSObject())
        viewModel.popoverWindowDidChange(window, isKey: false)
        viewModel.showDetail(of: try designReview(viewModel))

        viewModel.windowDidBecomeKey(window)

        #expect(viewModel.eventDetail == nil)
    }

    @Test func 他のウインドウが前面になっても詳細は閉じない() async throws {
        let viewModel = await Harness().loadedPopover()
        // 解放された NSObject のアドレスは再利用され、2 つの ObjectIdentifier が一致しうる。両方を保持して別のウインドウにする。
        let popoverWindow = NSObject()
        let otherWindow = NSObject()
        viewModel.popoverWindowDidChange(ObjectIdentifier(popoverWindow), isKey: false)
        viewModel.showDetail(of: try designReview(viewModel))

        viewModel.windowDidBecomeKey(ObjectIdentifier(otherWindow))

        withExtendedLifetime((popoverWindow, otherWindow)) {}
        #expect(viewModel.eventDetail != nil)
    }

    @Test func 日付が変わって選択日が今日に戻ると一覧に戻る() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))

        harness.dateProvider.set(SampleData.date(2026, 10, 25, 9, 0))
        viewModel.systemCalendarDidChange()

        #expect(viewModel.eventDetail == nil)
    }

    // MARK: - 読み直し

    @Test func 読み直しても同じ予定があれば新しい内容で詳細を続ける() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        let row = try designReview(viewModel)
        viewModel.showDetail(of: row)

        let original = try #require(SampleData.events.first { $0.id == row.id })
        let updated = CalendarEvent(
            accountID: original.accountID, id: original.eventID, calendarID: original.calendarID,
            title: "デザインレビュー（更新）", schedule: original.schedule,
            location: "会議室 B", notes: "更新後のメモ", attendance: .tentative
        )
        await harness.eventRepository.gate()
        viewModel.reload()
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }
        // 読み込み中は、直前の内容のまま詳細を続ける。
        #expect(viewModel.eventDetail?.title == "デザインレビュー")
        await harness.eventRepository.resume(at: 0, events: [updated])
        await viewModel.waitForLoad()

        #expect(viewModel.detailEventID == row.id)
        let detail = try #require(viewModel.eventDetail)
        #expect(detail.title == "デザインレビュー（更新）")
        #expect(detail.location == "会議室 B")
        #expect(detail.attendanceText == "未定")
        #expect(detail.participants.isEmpty)
        #expect(detail.meetingURL == nil)
        #expect(detail.notes.map { String($0.characters) } == "更新後のメモ")
    }

    @Test func 読み直した結果に予定がなければ一覧に戻る() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))

        await harness.eventRepository.gate()
        viewModel.reload()
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }
        let others = SampleData.events.filter { $0.title != "デザインレビュー" }
        await harness.eventRepository.resume(at: 0, events: others)
        await viewModel.waitForLoad()

        #expect(viewModel.phase == .loaded)
        #expect(viewModel.detailEventID == nil)
        #expect(viewModel.eventDetail == nil)
    }

    @Test func カレンダーのデータが変わって予定が消えたら一覧に戻る() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))

        await harness.eventRepository.gate()
        harness.notificationCenter.post(name: .calendarStoreDidChange, object: nil)
        while await harness.eventRepository.pendingCount < 1 { await Task.yield() }
        await harness.eventRepository.resume(at: 0, events: [])
        await viewModel.waitForLoad()

        #expect(viewModel.eventDetail == nil)
    }

    // MARK: - URL を開く

    @Test func リンクとボタンのURLをURLOpener経由で開く() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.showDetail(of: try designReview(viewModel))
        let detail = try #require(viewModel.eventDetail)

        #expect(viewModel.open(try #require(detail.meetingURL)))
        #expect(viewModel.open(try #require(detail.detailURL)))
        #expect(viewModel.open(URL(string: "http://example.com/a")!))

        #expect(harness.opener.openedURLs == [
            URL(string: "https://meet.google.com/xyz-uvwx-rst")!,
            URL(string: "https://example.com/events/design-review")!,
            URL(string: "http://example.com/a")!,
        ])
    }

    @Test(arguments: ["file:///etc/hosts", "mailto:a@example.com", "x-apple.systempreferences:com.apple", "javascript:alert(1)"])
    func httpとhttps以外のURLは開かない(text: String) async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()

        #expect(!viewModel.open(URL(string: text)!))
        #expect(harness.opener.openedURLs.isEmpty)
    }
}

@Suite struct CalendarFormatterScheduleTests {
    let formatter = CalendarFormatter(calendar: SampleData.calendar)

    func timed(_ start: Date, _ end: Date) -> EventSchedule { .timed(DateInterval(start: start, end: end)) }

    @Test func 同じ日に収まる予定は日付に開始と終了を続ける() {
        let text = formatter.scheduleText(timed(SampleData.date(2026, 10, 24, 14, 0), SampleData.date(2026, 10, 24, 15, 30)))
        #expect(text == "10月24日(土) 14:00〜15:30")
    }

    @Test func 日をまたぐ予定は終了にも日付を付ける() {
        let text = formatter.scheduleText(timed(SampleData.date(2026, 10, 29, 23, 0), SampleData.date(2026, 10, 30, 6, 30)))
        #expect(text == "10月29日(木) 23:00〜10月30日(金) 6:30")
    }

    @Test func 翌日の零時に終わる予定は終了にも日付を付ける() {
        let text = formatter.scheduleText(timed(SampleData.date(2026, 10, 24, 22, 0), SampleData.date(2026, 10, 25, 0, 0)))
        #expect(text == "10月24日(土) 22:00〜10月25日(日) 0:00")
    }

    @Test func 長さが0の予定は開始だけを出す() {
        let start = SampleData.date(2026, 10, 24, 9, 5)
        #expect(formatter.scheduleText(timed(start, start)) == "10月24日(土) 9:05")
    }

    @Test func 終日の1日は日付に終日を付ける() throws {
        let range = try DayRange(start: SampleData.day(2026, 10, 25), dayCount: 1, calendar: SampleData.calendar)
        #expect(formatter.scheduleText(.allDay(range)) == "10月25日(日) 終日")
    }

    @Test func 複数日の終日は最終日までを出す() throws {
        let range = try DayRange(start: SampleData.day(2026, 10, 27), dayCount: 3, calendar: SampleData.calendar)
        #expect(formatter.scheduleText(.allDay(range)) == "10月27日(火)〜10月29日(木) 終日")
    }

    @Test func 月をまたぐ終日も最終日を出す() throws {
        let range = try DayRange(start: SampleData.day(2026, 10, 31), dayCount: 2, calendar: SampleData.calendar)
        #expect(formatter.scheduleText(.allDay(range)) == "10月31日(土)〜11月1日(日) 終日")
    }
}

@Suite struct LinkedTextTests {
    func links(_ text: String) -> [URL] {
        LinkedText.attributed(text).runs.compactMap(\.link)
    }

    @Test func httpとhttpsのURLをリンクにする() {
        #expect(links("A http://example.com/a と https://example.com/b?x=1 です") == [
            URL(string: "http://example.com/a")!, URL(string: "https://example.com/b?x=1")!,
        ])
    }

    @Test func 文字列は変えない() {
        let text = "資料: https://example.com/doc.\n次の行"
        #expect(String(LinkedText.attributed(text).characters) == text)
    }

    @Test func スキームのない文字列とmailtoはリンクにしない() {
        #expect(links("readme.md と example.com と a@example.com と mailto:a@example.com").isEmpty)
    }

    @Test func URLがなければリンクはない() {
        #expect(links("会議室で実施").isEmpty)
        #expect(links("").isEmpty)
    }
}

@MainActor
@Suite struct CountdownCheckboxTests {
    func openDetail(titled title: String, in harness: Harness) async throws -> CalendarPopoverViewModel {
        let viewModel = await harness.loadedPopover()
        let row = try #require(viewModel.selectedSection.rows.first { $0.title == title })
        viewModel.showDetail(of: row)
        return viewModel
    }

    func openAllDayDetail(in harness: Harness) async throws -> CalendarPopoverViewModel {
        let viewModel = await harness.loadedPopover()
        viewModel.select(SampleData.day(2026, 10, 25))
        let row = try #require(viewModel.selectedSection.rows.first { $0.title == "引っ越し" })
        viewModel.showDetail(of: row)
        return viewModel
    }

    @Test func これから始まる予定は既定でオン() async throws {
        let viewModel = try await openDetail(titled: "デザインレビュー", in: Harness())
        #expect(viewModel.eventDetail?.includedInCountdown == true)
    }

    @Test func 開始済みの予定にも設定があり既定でオン() async throws {
        let viewModel = try await openDetail(titled: "朝会", in: Harness())
        #expect(viewModel.eventDetail?.includedInCountdown == true)
    }

    @Test func 辞退した予定にも設定があり既定でオンで説明用の印を持つ() async throws {
        let viewModel = try await openDetail(titled: "辞退した会議", in: Harness())
        #expect(viewModel.eventDetail?.includedInCountdown == true)
        #expect(viewModel.eventDetail?.isDeclined == true)
    }

    @Test func 辞退していない予定は辞退の印を持たない() async throws {
        let viewModel = try await openDetail(titled: "デザインレビュー", in: Harness())
        #expect(viewModel.eventDetail?.isDeclined == false)
    }

    @Test func 終日予定は対象になりえず詳細でチェックボックスの代わりに説明を出す状態になる() async throws {
        let viewModel = try await openAllDayDetail(in: Harness())
        #expect(viewModel.eventDetail?.includedInCountdown == false)
        #expect(viewModel.eventDetail?.canBeCountdownTarget == false)
    }

    @Test func 時刻付きの予定は対象になりうる() async throws {
        let viewModel = try await openDetail(titled: "デザインレビュー", in: Harness())
        #expect(viewModel.eventDetail?.canBeCountdownTarget == true)
    }

    @Test func 二十四時間より先の予定も既定でオン() async throws {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        viewModel.select(SampleData.day(2026, 10, 28))
        let row = try #require(viewModel.selectedSection.rows.first { $0.title == "新機能の企画会議" })
        viewModel.showDetail(of: row)
        #expect(viewModel.eventDetail?.includedInCountdown == true)
    }

    @Test func 外すと対象外として保存する() async throws {
        let harness = Harness()
        let viewModel = try await openDetail(titled: "デザインレビュー", in: harness)
        let id = try #require(viewModel.detailEventID)

        await viewModel.setIncludedInCountdown(false)

        #expect(viewModel.eventDetail?.includedInCountdown == false)
        #expect(await harness.countdownSettings.load().choices[id] == false)
    }

    @Test func 戻すと対象にした設定として保存する() async throws {
        let harness = Harness()
        let viewModel = try await openDetail(titled: "デザインレビュー", in: harness)
        let id = try #require(viewModel.detailEventID)

        await viewModel.setIncludedInCountdown(false)
        await viewModel.setIncludedInCountdown(true)

        #expect(viewModel.eventDetail?.includedInCountdown == true)
        #expect(await harness.countdownSettings.load().choices[id] == true)
    }

    @Test func 終日予定は対象にする操作をしても何も保存せず対象外のまま() async throws {
        let harness = Harness()
        let viewModel = try await openAllDayDetail(in: harness)

        await viewModel.setIncludedInCountdown(true)

        #expect(viewModel.eventDetail?.includedInCountdown == false)
        #expect(await harness.countdownSettings.load().choices.isEmpty)
        #expect(await harness.countdownSettings.updateCount == 0)
    }

    @Test func 終日予定に保存済みの選択があっても対象外のまま残る() async throws {
        let harness = Harness()
        let allDay = try #require(SampleData.events.first { $0.title == "引っ越し" })
        try await harness.countdownSettings.update { $0.set(allDay.id, isTarget: true) }
        let viewModel = try await openAllDayDetail(in: harness)

        #expect(viewModel.eventDetail?.includedInCountdown == false)
        #expect(viewModel.eventDetail?.canBeCountdownTarget == false)
        // 保存済みの値は消さない。
        #expect(await harness.countdownSettings.load().choices[allDay.id] == true)
    }

    @Test func 辞退した予定の設定も切り替えて保存できる() async throws {
        let harness = Harness()
        let viewModel = try await openDetail(titled: "辞退した会議", in: harness)
        let id = try #require(viewModel.detailEventID)

        await viewModel.setIncludedInCountdown(false)
        #expect(viewModel.eventDetail?.includedInCountdown == false)
        #expect(await harness.countdownSettings.load().choices[id] == false)

        await viewModel.setIncludedInCountdown(true)
        #expect(viewModel.eventDetail?.includedInCountdown == true)
        #expect(await harness.countdownSettings.load().choices[id] == true)
    }

    @Test func 開始済みの予定を切り替えても元に戻らない() async throws {
        let harness = Harness()
        let viewModel = try await openDetail(titled: "朝会", in: harness)
        let id = try #require(viewModel.detailEventID)

        await viewModel.setIncludedInCountdown(false)
        #expect(viewModel.eventDetail?.includedInCountdown == false)

        // 読み直しても、開始を過ぎた予定の設定は消えない。
        viewModel.reload()
        await viewModel.waitForLoad()
        #expect(viewModel.eventDetail?.includedInCountdown == false)
        #expect(await harness.countdownSettings.load().choices[id] == false)
    }

    @Test func すでにその状態なら保存しない() async throws {
        let harness = Harness()
        let viewModel = try await openDetail(titled: "デザインレビュー", in: harness)

        await viewModel.setIncludedInCountdown(true)

        #expect(await harness.countdownSettings.updateCount == 0)
        #expect(harness.notifier.revision == 0)
    }

    @Test func 保存できたら通知するが自分の通知では予定を読み直さない() async throws {
        let harness = Harness()
        let viewModel = try await openDetail(titled: "デザインレビュー", in: harness)
        let before = await harness.eventRepository.requests.count

        await viewModel.setIncludedInCountdown(false)
        viewModel.reloadIfChangedElsewhere()
        await viewModel.waitForLoad()

        #expect(harness.notifier.revision == 1)
        #expect(await harness.eventRepository.requests.count == before)
    }

    @Test func 保存に失敗したら表示を戻し通知しない() async throws {
        struct SaveFailure: Error {}
        let harness = Harness()
        let viewModel = try await openDetail(titled: "デザインレビュー", in: harness)
        await harness.countdownSettings.setFailure(SaveFailure())

        await viewModel.setIncludedInCountdown(false)

        #expect(viewModel.eventDetail?.includedInCountdown == true)
        #expect(harness.notifier.revision == 0)
        #expect(await harness.countdownSettings.load() == CountdownTargetSettings())
    }

    @Test func 読み直しても対象外は残る() async throws {
        let harness = Harness()
        let viewModel = try await openDetail(titled: "デザインレビュー", in: harness)
        await viewModel.setIncludedInCountdown(false)

        viewModel.reload()
        await viewModel.waitForLoad()

        #expect(viewModel.eventDetail?.includedInCountdown == false)
    }

    @Test func 詳細を開いていなければ何もしない() async {
        let harness = Harness()
        let viewModel = await harness.loadedPopover()
        await viewModel.setIncludedInCountdown(false)
        #expect(await harness.countdownSettings.updateCount == 0)
    }
}
