import Foundation
import MenuDateDomain
import MenuDatePreviewSupport
import Testing

@testable import MenuDatePresentation

@Suite struct MonthWeekLayoutTests {
    static let calendar = SampleData.calendar
    /// 2026-10-18（日）から 10-24（土）の週。
    static let weekStart = SampleData.day(2026, 10, 18)
    static let account = SampleData.googleAccount.id
    static let owner = SampleData.workCalendar

    static func day(_ offset: Int) -> CalendarDay { weekStart.adding(days: offset, calendar: calendar) }

    static func timed(_ id: String, _ title: String = "予定", day offset: Int, hour: Int, hours: Int = 1, endDay: Int? = nil) -> CalendarEvent {
        let start = calendar.date(byAdding: .hour, value: hour, to: day(offset).startDate(in: calendar))!
        let end = endDay.map { calendar.date(byAdding: .hour, value: hours, to: day($0).startDate(in: calendar))! }
            ?? calendar.date(byAdding: .hour, value: hours, to: start)!
        return CalendarEvent(
            accountID: owner.accountID, id: try! EventID(id), calendarID: owner.calendarID, title: title,
            schedule: .timed(DateInterval(start: start, end: end))
        )
    }

    /// `from` は週の先頭を 0 とした日の番号で、負なら前の週から始まる。
    static func allDay(_ id: String, _ title: String = "終日", from: Int, days: Int) -> CalendarEvent {
        CalendarEvent(
            accountID: owner.accountID, id: try! EventID(id), calendarID: owner.calendarID, title: title,
            schedule: .allDay(try! DayRange(start: day(from), dayCount: days, calendar: calendar))
        )
    }

    /// `AgendaBuilder` で日ごとに並べてから、週の配置を作る。
    static func layout(_ events: [CalendarEvent], now: Date = SampleData.date(2026, 10, 21, 12, 0)) -> MonthWeekLayout {
        let range = try! DayRange(start: day(-14), dayCount: 35, calendar: calendar)
        let agendas = AgendaBuilder().build(
            events: events, visibleCalendars: [owner.id], accountOrder: [account, owner.accountID],
            range: range, calendar: calendar
        )
        let eventsByDay = Dictionary(uniqueKeysWithValues: agendas.map { ($0.day, $0.events) })
        return MonthWeekLayout(
            days: (0..<7).map(day), eventsByDay: eventsByDay, color: { _ in owner.color },
            now: now, calendar: calendar, formatter: CalendarFormatter(calendar: calendar)
        )
    }

    static func item(_ layout: MonthWeekLayout, _ id: String) -> MonthWeekLayout.Item {
        layout.items.first { $0.id.eventID.rawValue == id }!
    }

    // MARK: - 割り当て

    @Test func 終日予定はバーになり複数日は列をまたぐ() {
        let layout = Self.layout([Self.allDay("trip", "出張", from: 2, days: 3)])
        let item = Self.item(layout, "trip")
        #expect(item.columns == 2..<5)
        #expect(item.lane == 0)
        #expect(item.kind == .bar(continuesFromPreviousWeek: false, continuesToNextWeek: false))
        #expect(item.title == "出張")
        #expect(item.color == Self.owner.color)
    }

    @Test func 日に収まる時刻付きの予定は開始時刻付きの行になる() {
        let layout = Self.layout([Self.timed("meeting", day: 3, hour: 9, hours: 1)])
        let item = Self.item(layout, "meeting")
        #expect(item.columns == 3..<4)
        #expect(item.kind == .timed(timeText: "9:00"))
    }

    @Test func 日をまたぐ時刻付きの予定はバーになる() {
        let layout = Self.layout([Self.timed("workshop", day: 1, hour: 15, hours: 20, endDay: nil)])
        let item = Self.item(layout, "workshop")
        #expect(item.columns == 1..<3)
        #expect(item.kind == .bar(continuesFromPreviousWeek: false, continuesToNextWeek: false))
    }

    @Test func バーは時刻付きの予定より上の行に置く() {
        let layout = Self.layout([
            Self.timed("early", day: 2, hour: 8),
            Self.allDay("bar", from: 1, days: 3),
        ])
        #expect(Self.item(layout, "bar").lane == 0)
        #expect(Self.item(layout, "early").lane == 1)
    }

    @Test func バーは開始の早い順に置き同じなら長い順に置く() {
        let layout = Self.layout([
            Self.allDay("short", from: 0, days: 1),
            Self.allDay("late", from: 1, days: 5),
            Self.allDay("long", from: 0, days: 3),
        ])
        #expect(Self.item(layout, "long").lane == 0)
        #expect(Self.item(layout, "short").lane == 1)
        // late は列 1 から 5 にかかり、long と重なるので 2 行目になる。short は列 0 だけなので late と重ならない。
        #expect(Self.item(layout, "late").lane == 1)
    }

    @Test func バーは重ならない範囲で一番小さい行に詰める() {
        let layout = Self.layout([
            Self.allDay("a", from: 0, days: 2),
            Self.allDay("b", from: 1, days: 2),
            Self.allDay("c", from: 2, days: 2),
        ])
        #expect(Self.item(layout, "a").lane == 0)
        #expect(Self.item(layout, "b").lane == 1)
        #expect(Self.item(layout, "c").lane == 0)
    }

    @Test func 開始と長さが同じバーは日の中の並び順で置く() {
        // 終日予定はタイトル順に並ぶ。
        let layout = Self.layout([
            Self.allDay("b", "ばなな", from: 0, days: 2),
            Self.allDay("a", "あっぷる", from: 0, days: 2),
        ])
        #expect(Self.item(layout, "a").lane == 0)
        #expect(Self.item(layout, "b").lane == 1)
    }

    @Test func 日に収まる予定は日ごとに並び順で空いている一番小さい行に置く() {
        let layout = Self.layout([
            Self.timed("t2", day: 2, hour: 14),
            Self.timed("t1", day: 2, hour: 9),
            Self.timed("other", day: 4, hour: 9),
        ])
        #expect(Self.item(layout, "t1").lane == 0)
        #expect(Self.item(layout, "t2").lane == 1)
        #expect(Self.item(layout, "other").lane == 0)
    }

    @Test func 日に収まる予定はバーが埋めた行を避ける() {
        let layout = Self.layout([
            Self.allDay("bar", from: 2, days: 1),
            Self.allDay("bar2", from: 2, days: 1),
            Self.timed("t", day: 2, hour: 9),
        ])
        #expect(Self.item(layout, "t").lane == 2)
    }

    @Test func バーが空けた行に別の列の日に収まる予定が入る() {
        let layout = Self.layout([
            Self.allDay("bar", from: 0, days: 1),
            Self.timed("t", day: 3, hour: 9),
        ])
        #expect(Self.item(layout, "t").lane == 0)
    }

    @Test func 同じ予定は複数の日に入っていても1つのバーにする() {
        let layout = Self.layout([Self.allDay("trip", from: 1, days: 4)])
        #expect(layout.items.count == 1)
        #expect(layout.items[0].columns == 1..<5)
    }

    @Test func タイトルがなければ代わりの文言にする() {
        let layout = Self.layout([Self.timed("untitled", "", day: 0, hour: 9)])
        #expect(Self.item(layout, "untitled").title == "(タイトルなし)")
    }

    // MARK: - 週をまたぐバー

    @Test func 前の週から続くバーは左端の継続を持つ() {
        let layout = Self.layout([Self.allDay("trip", from: -3, days: 5)])
        let item = Self.item(layout, "trip")
        #expect(item.columns == 0..<2)
        #expect(item.kind == .bar(continuesFromPreviousWeek: true, continuesToNextWeek: false))
    }

    @Test func 次の週へ続くバーは右端の継続を持つ() {
        let layout = Self.layout([Self.allDay("trip", from: 5, days: 4)])
        let item = Self.item(layout, "trip")
        #expect(item.columns == 5..<7)
        #expect(item.kind == .bar(continuesFromPreviousWeek: false, continuesToNextWeek: true))
    }

    @Test func 週をまたぐ終日予定は両側の継続を持つ() {
        let layout = Self.layout([Self.allDay("long", from: -2, days: 12)])
        #expect(Self.item(layout, "long").columns == 0..<7)
        #expect(Self.item(layout, "long").kind == .bar(continuesFromPreviousWeek: true, continuesToNextWeek: true))
    }

    @Test func 最終日で終わる終日予定は次の週へ続かない() {
        let layout = Self.layout([Self.allDay("end", from: 4, days: 3)])
        #expect(Self.item(layout, "end").kind == .bar(continuesFromPreviousWeek: false, continuesToNextWeek: false))
    }

    @Test func 週をまたぐ時刻付きの予定にも継続を付ける() {
        // 土曜 22:00 から翌週の月曜 2:00。
        let layout = Self.layout([Self.timed("night", day: 6, hour: 22, hours: 28)])
        #expect(Self.item(layout, "night").kind == .bar(continuesFromPreviousWeek: false, continuesToNextWeek: true))
        let previous = Self.layout([Self.timed("early", day: -1, hour: 22, hours: 4)])
        #expect(Self.item(previous, "early").kind == .bar(continuesFromPreviousWeek: true, continuesToNextWeek: false))
    }

    // MARK: - 過去

    @Test func 終わった予定は過去として扱う() {
        let layout = Self.layout([
            Self.timed("done", day: 2, hour: 9),
            Self.timed("future", day: 4, hour: 9),
            Self.allDay("pastBar", from: 0, days: 2),
            Self.allDay("todayBar", from: 3, days: 1),
        ])
        // now は 10-21（水、列 3）の 12:00。
        #expect(Self.item(layout, "done").isPast)
        #expect(!Self.item(layout, "future").isPast)
        #expect(Self.item(layout, "pastBar").isPast)
        #expect(!Self.item(layout, "todayBar").isPast)
    }

    @Test func 複数日のバーは最後の日で過去かを決める() {
        let layout = Self.layout([Self.allDay("span", from: 1, days: 4)])
        #expect(!Self.item(layout, "span").isPast)
    }

    // MARK: - 表示する件数

    /// 列 2 に時刻付きの予定を `count` 件置く。
    static func busyDay(_ count: Int) -> [CalendarEvent] {
        (0..<count).map { Self.timed("t\($0)", day: 2, hour: 8 + $0) }
    }

    @Test func 収まるときは何も隠さない() {
        let layout = Self.layout(Self.busyDay(3))
        let visible = layout.visible(laneCapacity: 3)
        #expect(visible.items.count == 3)
        #expect(visible.hiddenCountByColumn == [0, 0, 0, 0, 0, 0, 0])
    }

    @Test func 収まらないときは最後の行を他N件に使い隠した件数を数える() {
        let layout = Self.layout(Self.busyDay(6))
        let visible = layout.visible(laneCapacity: 3)
        // 行 0 と 1 だけを残し、行 2 は「他 4 件」の行に使う。
        #expect(visible.items.map(\.lane).sorted() == [0, 1])
        #expect(visible.hiddenCountByColumn == [0, 0, 4, 0, 0, 0, 0])
    }

    @Test func 隠した件数と残した件数の合計はその日の予定の件数に一致する() {
        let events = Self.busyDay(6) + [Self.timed("x", day: 4, hour: 9)]
        let layout = Self.layout(events)
        let visible = layout.visible(laneCapacity: 2)
        for column in 0..<7 {
            let shown = visible.items.filter { $0.columns.contains(column) }.count
            let total = layout.items.filter { $0.columns.contains(column) }.count
            #expect(shown + visible.hiddenCountByColumn[column] == total)
        }
        #expect(visible.hiddenCountByColumn[2] == 5)
        #expect(visible.hiddenCountByColumn[4] == 0)
    }

    @Test func 隠した列に他N件の行を空けるため最後の行のバーも隠す() {
        // 行 0 のバーは 0〜2 列、行 1 は 1 列だけに予定が 2 件（行 1 と 2）。容量 2 なら行 2 の予定が隠れ、列 1 の行 1 も隠れる。
        let events = [
            Self.allDay("bar", from: 0, days: 3),
            Self.timed("a", day: 1, hour: 9),
            Self.timed("b", day: 1, hour: 10),
        ]
        let layout = Self.layout(events)
        let visible = layout.visible(laneCapacity: 2)
        #expect(visible.items.map(\.id.eventID.rawValue) == ["bar"])
        #expect(visible.hiddenCountByColumn == [0, 2, 0, 0, 0, 0, 0])
    }

    @Test func 隠したバーがかかる別の列でも最後の行を空ける() {
        // 容量 2。列 0 は 3 件で、行 1 のバー（列 0〜1）が最後の行として隠れる。
        // すると列 1 に隠した予定ができ、列 1 の行 1 にある別の予定 c も隠れる。
        let events = [
            Self.allDay("top", from: 0, days: 1),
            Self.allDay("mid", from: 0, days: 2),
            Self.timed("a", day: 0, hour: 9),
            Self.timed("c", day: 1, hour: 9),
        ]
        let layout = Self.layout(events)
        #expect(Self.item(layout, "top").lane == 1 || Self.item(layout, "mid").lane == 1)
        let visible = layout.visible(laneCapacity: 2)
        let shownIDs = Set(visible.items.map(\.id.eventID.rawValue))
        #expect(shownIDs.isDisjoint(with: ["a"]))
        for column in 0..<2 {
            // 隠した予定がある列には、最後の行に残った予定がない。
            if visible.hiddenCountByColumn[column] > 0 {
                #expect(!visible.items.contains { $0.lane == 1 && $0.columns.contains(column) })
            }
        }
        let total = layout.items.filter { $0.columns.contains(1) }.count
        let shown = visible.items.filter { $0.columns.contains(1) }.count
        #expect(shown + visible.hiddenCountByColumn[1] == total)
    }

    @Test func 隠した予定がない列の最後の行は残す() {
        let events = Self.busyDay(4) + [Self.timed("a", day: 5, hour: 9), Self.timed("b", day: 5, hour: 10)]
        let visible = Self.layout(events).visible(laneCapacity: 2)
        #expect(visible.items.contains { $0.id.eventID.rawValue == "b" })
        #expect(visible.hiddenCountByColumn[5] == 0)
    }

    @Test func 容量が0以下ならすべて隠す() {
        let layout = Self.layout(Self.busyDay(2) + [Self.allDay("bar", from: 1, days: 3)])
        for capacity in [0, -1] {
            let visible = layout.visible(laneCapacity: capacity)
            #expect(visible.items.isEmpty)
            #expect(visible.hiddenCountByColumn == [0, 1, 3, 1, 0, 0, 0])
        }
    }

    @Test func 容量が1なら全件を他N件にまとめる() {
        let layout = Self.layout(Self.busyDay(2))
        let visible = layout.visible(laneCapacity: 1)
        #expect(visible.items.isEmpty)
        #expect(visible.hiddenCountByColumn[2] == 2)
    }

    @Test func 予定がない週は空である() {
        let layout = Self.layout([])
        #expect(layout.items.isEmpty)
        #expect(layout.visible(laneCapacity: 3) == .init(items: [], hiddenCountByColumn: Array(repeating: 0, count: 7)))
    }
}
