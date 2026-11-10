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

    func countdown(_ events: [CalendarEvent], excluding exclusions: CountdownExclusions = CountdownExclusions()) -> NextEventCountdown? {
        NextEventCountdown.next(in: events, excluding: exclusions, at: now)
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

    @Test func 終日予定は対象にしない() {
        #expect(countdown([allDay("a")]) == nil)
    }

    @Test func 辞退した予定は対象にしない() {
        #expect(countdown([timed("a", after: 600, attendance: .declined)]) == nil)
        #expect(countdown([timed("a", after: 600, attendance: .needsAction)])?.remainingMinutes == 10)
        #expect(countdown([timed("a", after: 600, attendance: .notApplicable)])?.remainingMinutes == 10)
    }

    @Test func 除外した予定は対象にせず次の予定を選ぶ() {
        let first = timed("first", after: 600)
        let second = timed("second", after: 1800)
        var exclusions = CountdownExclusions()
        exclusions.exclude(first.id, start: now.addingTimeInterval(600))
        #expect(countdown([first, second], excluding: exclusions)?.remainingMinutes == 30)
        exclusions.include(first.id)
        #expect(countdown([first, second], excluding: exclusions)?.remainingMinutes == 10)
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

    @Test func 対象になり得るかは24時間より先でも真() {
        #expect(NextEventCountdown.canBeCounted(timed("far", after: 3 * 86_400), at: now))
        #expect(NextEventCountdown.canBeCounted(timed("soon", after: 60), at: now))
        #expect(!NextEventCountdown.canBeCounted(timed("started", after: -1), at: now))
        #expect(!NextEventCountdown.canBeCounted(timed("declined", after: 60, attendance: .declined), at: now))
        #expect(!NextEventCountdown.canBeCounted(allDay("allDay"), at: now))
    }
}

@Suite struct CountdownExclusionsTests {
    let account = TestSupport.accountID("a")
    let calendar = TestSupport.calendar()
    let start = TestSupport.date(2026, 10, 24, 14, 0)

    func identity(_ id: String, account: AccountID? = nil, calendarID: String = "work") -> CalendarEvent.Identity {
        CalendarEvent.Identity(
            accountID: account ?? self.account, calendarID: TestSupport.calendarID(calendarID), eventID: TestSupport.eventID(id)
        )
    }

    @Test func 初めは何も除外していない() {
        #expect(!CountdownExclusions().isExcluded(identity("a")))
    }

    @Test func 除外して戻せる() {
        var exclusions = CountdownExclusions()
        exclusions.exclude(identity("a"), start: start)
        #expect(exclusions.isExcluded(identity("a")))
        exclusions.include(identity("a"))
        #expect(!exclusions.isExcluded(identity("a")))
    }

    @Test func 同じ予定IDでもアカウントとカレンダーが違えば別の予定() {
        var exclusions = CountdownExclusions()
        exclusions.exclude(identity("a"), start: start)
        #expect(!exclusions.isExcluded(identity("a", account: TestSupport.accountID("b"))))
        #expect(!exclusions.isExcluded(identity("a", calendarID: "personal")))
    }

    @Test func 戻していない予定を戻しても何も起きない() {
        var exclusions = CountdownExclusions()
        exclusions.include(identity("a"))
        #expect(exclusions == CountdownExclusions())
    }

    @Test func 開始が指定の時刻より前の項目を消す() {
        var exclusions = CountdownExclusions()
        exclusions.exclude(identity("past"), start: start.addingTimeInterval(-1))
        exclusions.exclude(identity("now"), start: start)
        exclusions.exclude(identity("future"), start: start.addingTimeInterval(1))
        exclusions.removeEntries(startingBefore: start)
        #expect(!exclusions.isExcluded(identity("past")))
        #expect(exclusions.isExcluded(identity("now")))
        #expect(exclusions.isExcluded(identity("future")))
    }
}
