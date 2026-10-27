import CoreGraphics
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

@Suite struct MonthRowGeometryTests {
    static let geometry = MonthRowGeometry(size: CGSize(width: 700, height: 120))

    /// 行の高さ 120 は、(120 - 24 - 2) / 17 の切り捨てで 5 行。
    static let capacity = 5

    typealias Layout = MonthWeekLayoutTests

    static func visible(_ events: [CalendarEvent], capacity: Int = capacity) -> MonthWeekLayout.Visible {
        Layout.layout(events).visible(laneCapacity: capacity)
    }

    static func point(column: Int, lane: Int) -> CGPoint {
        CGPoint(x: CGFloat(column) * 100 + 50, y: MonthRowGeometry.dayHeaderHeight + CGFloat(lane) * MonthRowGeometry.laneHeight + 8)
    }

    @Test(arguments: [
        (CGFloat(120), 5), (CGFloat(116), 5), (CGFloat(100), 4), (CGFloat(69), 2), (CGFloat(26), 0), (CGFloat(10), 0),
    ])
    func 行の高さから入る予定の行の数を求める(rowHeight: CGFloat, expected: Int) {
        #expect(MonthRowGeometry.laneCapacity(rowHeight: rowHeight) == expected)
        #expect(MonthRowGeometry(size: CGSize(width: 700, height: rowHeight)).laneCapacity == expected)
    }

    @Test func 位置から列を求める() {
        #expect(Self.geometry.column(at: 0) == 0)
        #expect(Self.geometry.column(at: 99.9) == 0)
        #expect(Self.geometry.column(at: 100) == 1)
        #expect(Self.geometry.column(at: 699) == 6)
        #expect(Self.geometry.column(at: -5) == 0)
        #expect(Self.geometry.column(at: 900) == 6)
    }

    @Test func 日の数字の領域は日のマスになる() {
        let visible = Self.visible([Layout.timed("a", day: 2, hour: 9)])
        #expect(Self.geometry.target(at: CGPoint(x: 250, y: 10), visible: visible) == .day(2))
    }

    @Test func 予定の行は予定になる() {
        let event = Layout.timed("a", day: 2, hour: 9)
        let visible = Self.visible([event])
        #expect(Self.geometry.target(at: Self.point(column: 2, lane: 0), visible: visible) == .event(event.id))
        #expect(Self.geometry.target(at: Self.point(column: 3, lane: 0), visible: visible) == .day(3))
        #expect(Self.geometry.target(at: Self.point(column: 2, lane: 1), visible: visible) == .day(2))
    }

    @Test func バーはかかるすべての列で予定になる() {
        let trip = Layout.allDay("trip", from: 1, days: 3)
        let visible = Self.visible([trip])
        for column in 1...3 {
            #expect(Self.geometry.target(at: Self.point(column: column, lane: 0), visible: visible) == .event(trip.id))
        }
        #expect(Self.geometry.target(at: Self.point(column: 4, lane: 0), visible: visible) == .day(4))
    }

    @Test func 入りきらない日の最後の行は他N件になる() {
        let events = (0..<7).map { Layout.timed("e\($0)", day: 3, hour: 8 + $0) }
        let visible = Self.visible(events)
        #expect(visible.hiddenCountByColumn[3] == 3)
        #expect(Self.geometry.target(at: Self.point(column: 3, lane: Self.capacity - 1), visible: visible) == .more(3))
        #expect(Self.geometry.target(at: Self.point(column: 3, lane: 0), visible: visible) == .event(events[0].id))
        #expect(Self.geometry.target(at: Self.point(column: 2, lane: Self.capacity - 1), visible: visible) == .day(2))
    }

    @Test func 行の数を超える位置は日のマスになる() {
        let visible = Self.visible([Layout.timed("a", day: 0, hour: 9)])
        #expect(Self.geometry.target(at: CGPoint(x: 50, y: 119), visible: visible) == .day(0))
    }

    @Test func 予定の枠は描画と同じ寸法になる() {
        let rect = Self.geometry.laneRect(lane: 1, columns: 2..<5)
        #expect(rect.minX == 200 + MonthRowGeometry.horizontalInset)
        #expect(rect.width == 300 - 2 * MonthRowGeometry.horizontalInset)
        #expect(rect.minY == MonthRowGeometry.dayHeaderHeight + MonthRowGeometry.laneHeight)
        #expect(rect.height == MonthRowGeometry.laneHeight)
    }
}
