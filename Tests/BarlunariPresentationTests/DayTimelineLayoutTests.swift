import Testing

@testable import BarlunariPresentation

@Suite struct DayTimelineLayoutTests {
    typealias Layout = DayTimelineLayout<String>

    private func layout(_ entries: [(String, Int, Int)]) -> Layout {
        Layout(entries: entries.map { .init(id: $0.0, startMinute: $0.1, endMinute: $0.2) })
    }

    private func block(_ layout: Layout, _ id: String) -> Layout.Block {
        layout.blocks.first { $0.id == id }!
    }

    @Test func 重ならない予定は全幅で並ぶ() {
        let result = layout([("a", 600, 660), ("b", 660, 720), ("c", 900, 960)])
        #expect(result.blocks.map(\.column) == [0, 0, 0])
        #expect(result.blocks.map(\.columnCount) == [1, 1, 1])
    }

    @Test func 重なる予定は開始順に空いている最初の列へ入り_幅は列数で等分する() {
        let result = layout([("a", 600, 720), ("b", 630, 690), ("c", 700, 760)])
        #expect(block(result, "a").column == 0)
        #expect(block(result, "b").column == 1)
        // c は a と重なるが、b は 690 で終わっているので列 1 に入る。
        #expect(block(result, "c").column == 1)
        #expect(result.blocks.allSatisfy { $0.columnCount == 2 })
    }

    @Test func 推移的に重なるまとまりは同じ列数になり_別のまとまりは影響しない() {
        let result = layout([("a", 600, 660), ("b", 630, 700), ("c", 690, 750), ("d", 900, 960)])
        #expect(block(result, "a").columnCount == 2)
        #expect(block(result, "c").columnCount == 2)
        #expect(block(result, "c").column == 0)
        #expect(block(result, "d").columnCount == 1)
    }

    @Test func 開始が同じなら長い予定が先の列に入る() {
        let result = layout([("short", 600, 660), ("long", 600, 780)])
        #expect(block(result, "long").column == 0)
        #expect(block(result, "short").column == 1)
    }

    @Test func 短い予定は表示上の長さの下限を持ち_位置は開始のまま() {
        let result = layout([("a", 600, 610)])
        #expect(block(result, "a").startMinute == 600)
        #expect(block(result, "a").displayEndMinute == 630)
    }

    @Test func 下限の長さで重なる予定も別の列になる() {
        // a は 10:00〜10:05 だが、表示上は 10:30 まで。10:20 開始の b は重なる。
        let result = layout([("a", 600, 605), ("b", 620, 680)])
        #expect(block(result, "b").column == 1)
        #expect(block(result, "a").columnCount == 2)
    }

    @Test func 一日の終わりを超えない() {
        let result = layout([("late", 1430, 1440), ("zero", 1440, 1440)])
        #expect(result.blocks.allSatisfy { $0.displayEndMinute <= 1440 })
        #expect(block(result, "zero").startMinute == 1439)
    }

    @Test func 同じ開始と終了なら入力の順に列へ入る() {
        let result = layout([("x", 600, 660), ("y", 600, 660), ("z", 600, 660)])
        #expect(result.blocks.map(\.id) == ["x", "y", "z"])
        #expect(result.blocks.map(\.column) == [0, 1, 2])
    }

    @Test func 予定がなければ空() {
        #expect(layout([]).blocks.isEmpty)
    }
}

@Suite struct DayScheduleScrollTests {
    @Test func 今日は現在時刻の60分前を30分単位に切り捨てる() {
        #expect(DayScheduleScroll.targetMinute(currentMinute: 14 * 60 + 20, firstTimedStartMinute: 9 * 60) == 13 * 60)
    }

    @Test func 今日でなければ最初の予定の60分前() {
        #expect(DayScheduleScroll.targetMinute(currentMinute: nil, firstTimedStartMinute: 10 * 60 + 45) == 9 * 60 + 30)
    }

    @Test func 予定がなければ8時() {
        #expect(DayScheduleScroll.targetMinute(currentMinute: nil, firstTimedStartMinute: nil) == 8 * 60)
    }

    @Test func 開始時刻は0時より前にならない() {
        #expect(DayScheduleScroll.targetMinute(currentMinute: 20, firstTimedStartMinute: nil) == 0)
        #expect(DayScheduleScroll.targetMinute(currentMinute: nil, firstTimedStartMinute: 30) == 0)
    }

    @Test func 末尾まで届く位置なら目標の30分ごとの位置() {
        #expect(DayTimelineMetrics.reachableSlot(for: 9 * 60, viewportHeight: 600) == 18)
    }

    @Test func 末尾で止まる位置なら届く一番遅い30分ごとの位置() {
        // 内容 1168pt、枠 1000pt なら、届くのは 168pt まで。30 分 24pt なので 7 番目の 3:30。
        #expect(DayTimelineMetrics.contentHeight == 1168)
        #expect(DayTimelineMetrics.reachableSlot(for: 8 * 60, viewportHeight: 1000) == 7)
    }

    @Test func 枠が内容より高ければ0時() {
        #expect(DayTimelineMetrics.reachableSlot(for: 8 * 60, viewportHeight: 1300) == 0)
    }
}
