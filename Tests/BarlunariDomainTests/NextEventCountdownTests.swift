import Foundation
import Testing
@testable import BarlunariDomain

@Suite struct NextEventCountdownTests {
    let now = TestSupport.date(2026, 10, 24, 12, 0)
    let account = TestSupport.accountID("a")
    let work = TestSupport.calendarID("work")

    func timed(
        _ id: String, after seconds: TimeInterval, duration: TimeInterval = 3600,
        attendance: AttendanceStatus = .accepted
    ) -> CalendarEvent {
        CalendarEvent(
            accountID: account, id: TestSupport.eventID(id), calendarID: work, title: id,
            schedule: .timed(DateInterval(start: now.addingTimeInterval(seconds), duration: duration)),
            attendance: attendance
        )
    }

    func allDay(_ id: String) -> CalendarEvent {
        CalendarEvent(
            accountID: account, id: TestSupport.eventID(id), calendarID: work, title: id,
            schedule: .allDay(TestSupport.range(TestSupport.day(2026, 10, 25), days: 1))
        )
    }

    func countdown(_ events: [CalendarEvent], settings: CountdownTargetSettings = CountdownTargetSettings()) -> NextEventCountdown? {
        NextEventCountdown.next(in: events, settings: settings, at: now, calendar: TestSupport.calendar())
    }

    @Test(arguments: [
        (30.0, 1), (60.0, 1), (61.0, 2), (120.0, 2), (121.0, 3), (3600.0, 60), (5100.0, 85), (86_340.0, 1439),
    ])
    func 残りの分は秒の端数を切り上げる(seconds: Double, minutes: Int) {
        #expect(countdown([timed("a", after: seconds)])?.remainingMinutes == minutes)
    }

    @Test func 開始の30秒前は00_01になり00_00を出さない() {
        let result = countdown([timed("a", after: 30)])
        #expect(result?.hours == 0)
        #expect(result?.minutes == 1)
    }

    @Test func 残り24時間未満の境界() {
        #expect(countdown([timed("a", after: 86_340)])?.remainingMinutes == 1439)
        #expect(countdown([timed("a", after: 86_341)]) == nil)
        #expect(countdown([timed("a", after: 86_400)]) == nil)
    }

    @Test func 時間と分の成分に分ける() {
        let result = countdown([timed("a", after: 85 * 60)])
        #expect(result?.hours == 1)
        #expect(result?.minutes == 25)
        let max = countdown([timed("a", after: 1439 * 60)])
        #expect(max?.hours == 23)
        #expect(max?.minutes == 59)
    }

    @Test func 開始済みの予定と開始ちょうどの予定は対象にしない() {
        #expect(countdown([timed("a", after: -60)]) == nil)
        #expect(countdown([timed("a", after: 0)]) == nil)
    }

    @Test func 終日予定は既定では対象にしない() {
        #expect(countdown([allDay("a")]) == nil)
    }

    @Test func 終日予定を対象にするとその日の0時までの残り時間になる() {
        let event = allDay("a")
        var settings = CountdownTargetSettings()
        settings.set(event.id, isTarget: true)
        let result = countdown([event], settings: settings)
        // now は 10/24 12:00、終日予定は 10/25 の 0:00 開始なので 12 時間。
        #expect(result?.start == TestSupport.date(2026, 10, 25, 0, 0))
        #expect(result?.remainingMinutes == 720)
    }

    @Test func 辞退した予定は設定にかかわらず数えず他の参加状況は判定に使わない() {
        let declined = timed("a", after: 600, attendance: .declined)
        #expect(countdown([declined]) == nil)
        var settings = CountdownTargetSettings()
        settings.set(declined.id, isTarget: true)
        #expect(countdown([declined], settings: settings) == nil)
        #expect(countdown([timed("a", after: 600, attendance: .needsAction)])?.remainingMinutes == 10)
        #expect(countdown([timed("a", after: 600, attendance: .tentative)])?.remainingMinutes == 10)
        #expect(countdown([timed("a", after: 600, attendance: .notApplicable)])?.remainingMinutes == 10)
    }

    @Test func 辞退した予定を飛ばして次の予定を選ぶ() {
        let declined = timed("declined", after: 600, attendance: .declined)
        #expect(countdown([declined, timed("next", after: 1800)])?.remainingMinutes == 30)
    }

    @Test func 対象外にした予定は数えず次の予定を選ぶ() {
        let first = timed("first", after: 600)
        let second = timed("second", after: 1800)
        var settings = CountdownTargetSettings()
        settings.set(first.id, isTarget: false)
        #expect(countdown([first, second], settings: settings)?.remainingMinutes == 30)
        settings.set(first.id, isTarget: true)
        #expect(countdown([first, second], settings: settings)?.remainingMinutes == 10)
    }

    @Test func 開始が最も早い予定を選ぶ() {
        let result = countdown([timed("late", after: 3000), timed("early", after: 900), timed("mid", after: 1800)])
        #expect(result?.remainingMinutes == 15)
        #expect(result?.start == now.addingTimeInterval(900))
    }

    @Test func 対象の予定がなければnil() {
        #expect(countdown([]) == nil)
    }

    @Test func 表示が次に変わる時刻() {
        let start = now.addingTimeInterval(125 * 60 + 30)
        // 残り 126 分（切り上げ）。次に変わるのは、残りが 125 分になる開始の 125 分前。
        let result = NextEventCountdown(start: start, now: now)
        #expect(result?.remainingMinutes == 126)
        #expect(result?.nextChange == start.addingTimeInterval(-125 * 60))
        if let change = result?.nextChange {
            #expect(NextEventCountdown(start: start, now: change)?.remainingMinutes == 125)
        }
    }

    @Test func 残り1分なら開始の時刻に変わる() {
        let start = now.addingTimeInterval(45)
        let result = NextEventCountdown(start: start, now: now)
        #expect(result?.remainingMinutes == 1)
        #expect(result?.nextChange == start)
        #expect(NextEventCountdown(start: start, now: start) == nil)
    }

    @Test func 分の境目ちょうどでは次の値に変わる() {
        let start = now.addingTimeInterval(61)
        #expect(NextEventCountdown(start: start, now: now)?.remainingMinutes == 2)
        let change = NextEventCountdown(start: start, now: now)!.nextChange
        #expect(change == now.addingTimeInterval(1))
        #expect(NextEventCountdown(start: start, now: change)?.remainingMinutes == 1)
    }
}

@Suite struct CountdownTargetSettingsTests {
    let account = TestSupport.accountID("a")
    let work = TestSupport.calendarID("work")
    let start = TestSupport.date(2026, 10, 24, 14, 0)

    func event(_ id: String, account: AccountID? = nil, calendarID: CalendarID? = nil, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(
            accountID: account ?? self.account, id: TestSupport.eventID(id), calendarID: calendarID ?? work, title: id,
            schedule: allDay
                ? .allDay(TestSupport.range(TestSupport.day(2026, 10, 25), days: 1))
                : .timed(DateInterval(start: start, duration: 3600))
        )
    }

    @Test func 既定は時刻付きが対象で終日が対象外() {
        let settings = CountdownTargetSettings()
        #expect(settings.isTarget(event("a")))
        #expect(!settings.isTarget(event("a", allDay: true)))
    }

    @Test func 辞退した予定の設定値も既定も参加状況に左右されない() {
        let declined = CalendarEvent(
            accountID: account, id: TestSupport.eventID("d"), calendarID: work, title: "d",
            schedule: .timed(DateInterval(start: start, duration: 3600)), attendance: .declined
        )
        #expect(CountdownTargetSettings().isTarget(declined))
        var settings = CountdownTargetSettings()
        settings.set(declined.id, isTarget: false)
        #expect(!settings.isTarget(declined))
    }

    @Test func 選んだ値が既定より優先され何度でも切り替えられる() {
        var settings = CountdownTargetSettings()
        let timed = event("a")
        let allDay = event("b", allDay: true)
        settings.set(timed.id, isTarget: false)
        settings.set(allDay.id, isTarget: true)
        #expect(!settings.isTarget(timed))
        #expect(settings.isTarget(allDay))
        settings.set(timed.id, isTarget: true)
        #expect(settings.isTarget(timed))
    }

    @Test func 同じ予定IDでもアカウントとカレンダーが違えば別の予定() {
        var settings = CountdownTargetSettings()
        settings.set(event("a").id, isTarget: false)
        #expect(settings.isTarget(event("a", account: TestSupport.accountID("b"))))
        #expect(settings.isTarget(event("a", calendarID: TestSupport.calendarID("personal"))))
    }
}
