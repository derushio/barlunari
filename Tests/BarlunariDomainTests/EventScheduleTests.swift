import Foundation
@testable import BarlunariDomain
import Testing

@Suite struct EventScheduleTests {
    private let calendar = TestSupport.calendar()
    private let today = try! CalendarDay(year: 2026, month: 10, day: 24)

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func timed(from start: Date, to end: Date) -> EventSchedule {
        .timed(DateInterval(start: start, end: end))
    }

    // MARK: - hasEnded

    @Test func 時刻付きの予定は終了時刻ちょうどに終わったことになる() {
        let schedule = timed(from: date(24, 10), to: date(24, 11))
        #expect(!schedule.hasEnded(on: today, at: date(24, 10, 59), calendar: calendar))
        #expect(schedule.hasEnded(on: today, at: date(24, 11), calendar: calendar))
    }

    @Test func 終日予定は現在の日より前の日だけ終わっている() throws {
        let range = try DayRange(start: today, dayCount: 3, calendar: calendar)
        let schedule = EventSchedule.allDay(range)
        let now = date(24, 12)
        #expect(schedule.hasEnded(on: today.adding(days: -1, calendar: calendar), at: now, calendar: calendar))
        #expect(!schedule.hasEnded(on: today, at: now, calendar: calendar))
        #expect(!schedule.hasEnded(on: today.adding(days: 1, calendar: calendar), at: now, calendar: calendar))
    }

    @Test func 日をまたぐ予定は表示する日にかかわらず終了時刻で判定する() {
        let schedule = timed(from: date(24, 23), to: date(25, 6))
        let nextDay = today.adding(days: 1, calendar: calendar)
        #expect(!schedule.hasEnded(on: nextDay, at: date(25, 5), calendar: calendar))
        #expect(schedule.hasEnded(on: nextDay, at: date(25, 7), calendar: calendar))
    }

    // MARK: - span

    @Test func 終日予定の収まり方は終日になる() throws {
        let schedule = EventSchedule.allDay(try DayRange(start: today, dayCount: 1, calendar: calendar))
        #expect(schedule.span(on: today, calendar: calendar) == .allDay)
    }

    @Test func その日に収まる予定は開始と終了を持つ() {
        let schedule = timed(from: date(24, 10), to: date(24, 11))
        #expect(schedule.span(on: today, calendar: calendar) == .withinDay(start: date(24, 10), end: date(24, 11)))
    }

    @Test func 翌日へ続く予定は開始日に終了を省く() {
        let schedule = timed(from: date(24, 23), to: date(25, 6, 30))
        #expect(schedule.span(on: today, calendar: calendar) == .startsOnDay(start: date(24, 23)))
    }

    @Test func 前日から続く予定は終了日に開始を省く() {
        let schedule = timed(from: date(24, 23), to: date(25, 6, 30))
        let nextDay = today.adding(days: 1, calendar: calendar)
        #expect(schedule.span(on: nextDay, calendar: calendar) == .endsOnDay(end: date(25, 6, 30)))
    }

    @Test func 前後にはみ出す予定はその日を丸ごと埋める() {
        let schedule = timed(from: date(23, 22), to: date(25, 8))
        #expect(schedule.span(on: today, calendar: calendar) == .entireDay)
    }

    @Test func 終了が翌日の零時ちょうどなら翌日へ続くとは見なさない() {
        let schedule = timed(from: date(24, 22), to: date(25, 0))
        #expect(schedule.span(on: today, calendar: calendar) == .withinDay(start: date(24, 22), end: date(25, 0)))
    }
}
