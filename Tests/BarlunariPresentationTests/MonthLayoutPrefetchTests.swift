import Foundation
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

/// 先に用意する週の範囲の計算と、予定の配置の記憶。
@Suite struct MonthPrefetchTests {
    @Test func 見えている週を含めず前後を近い順に交互に並べる() {
        let weeks = MonthPrefetch.weeks(firstVisibleWeek: 50, weekCount: 105, radius: 3)

        // 見えている週は 50..<57。後ろの 57、前の 49、後ろの 58、前の 48 ... の順。
        #expect(weeks == [57, 49, 58, 48, 59, 47])
    }

    @Test func 範囲は週の数の中に収める() {
        #expect(MonthPrefetch.weeks(firstVisibleWeek: 0, weekCount: 105, radius: 2) == [7, 8])
        #expect(MonthPrefetch.weeks(firstVisibleWeek: 98, weekCount: 105, radius: 2) == [97, 96])
        #expect(MonthPrefetch.weeks(firstVisibleWeek: 0, weekCount: 5, radius: 4).isEmpty)
    }

    @Test func 半径が0以下なら何も用意しない() {
        #expect(MonthPrefetch.weeks(firstVisibleWeek: 10, weekCount: 105, radius: 0).isEmpty)
        #expect(MonthPrefetch.weeks(firstVisibleWeek: 10, weekCount: 105, radius: -1).isEmpty)
    }

    @Test func 既定の範囲は有限で重複がなく見えている週を含まない() {
        let first = 40
        let weeks = MonthPrefetch.weeks(firstVisibleWeek: first, weekCount: 105)

        #expect(weeks.count == MonthPrefetch.radius * 2)
        #expect(Set(weeks).count == weeks.count)
        #expect(weeks.allSatisfy { !(first..<(first + MonthPrefetch.visibleWeeks)).contains($0) })
        #expect(weeks.count < 105)
    }
}

@Suite struct MonthWeekLayoutCacheTests {
    static let timeline = try! WeekTimeline(today: SampleData.today, firstWeekday: SampleData.calendar.firstWeekday)

    static func stamp(data: Int = 0, clock: Int = 0, minute: Int = 0) -> MonthWeekLayoutCache.Stamp {
        MonthWeekLayoutCache.Stamp(dataRevision: data, clockRevision: clock, timeline: timeline, minute: minute)
    }

    static func layout() -> MonthWeekLayout {
        MonthWeekLayout(
            days: timeline.days(inWeek: 10), eventsByDay: [:], color: { _ in nil },
            now: SampleData.now, calendar: SampleData.calendar, formatter: CalendarFormatter(calendar: SampleData.calendar)
        )
    }

    @Test func 同じ印では二度目から作らない() {
        var cache = MonthWeekLayoutCache()
        var made = 0
        for _ in 0..<3 {
            _ = cache.layout(at: 5, stamp: Self.stamp()) { made += 1; return Self.layout() }
        }

        #expect(made == 1)
        #expect(cache.count == 1)
    }

    @Test(arguments: [
        ("読み込み", MonthWeekLayoutCache.Stamp(dataRevision: 1, clockRevision: 0, timeline: MonthWeekLayoutCacheTests.timeline, minute: 0)),
        ("日付の変化", MonthWeekLayoutCache.Stamp(dataRevision: 0, clockRevision: 1, timeline: MonthWeekLayoutCacheTests.timeline, minute: 0)),
        ("1 分の経過", MonthWeekLayoutCache.Stamp(dataRevision: 0, clockRevision: 0, timeline: MonthWeekLayoutCacheTests.timeline, minute: 1)),
    ])
    func 印が変わると覚えているものをすべて捨てる(reason: String, changed: MonthWeekLayoutCache.Stamp) {
        var cache = MonthWeekLayoutCache()
        for week in 0..<5 { _ = cache.layout(at: week, stamp: Self.stamp()) { Self.layout() } }
        #expect(cache.count == 5)

        var made = 0
        _ = cache.layout(at: 2, stamp: changed) { made += 1; return Self.layout() }

        #expect(made == 1, Comment(rawValue: reason))
        #expect(cache.count == 1)
        #expect(cache.invalidationCount == 1)
        #expect(cache.stamp == changed)
    }

    @Test func 週の並びが作り直されると捨てる() throws {
        var cache = MonthWeekLayoutCache()
        _ = cache.layout(at: 1, stamp: Self.stamp()) { Self.layout() }
        let rebuilt = try WeekTimeline(today: SampleData.today, firstWeekday: 2)
        let stamp = MonthWeekLayoutCache.Stamp(dataRevision: 0, clockRevision: 0, timeline: rebuilt, minute: 0)

        _ = cache.layout(at: 2, stamp: stamp) { Self.layout() }

        #expect(!cache.contains(1))
        #expect(cache.contains(2))
    }

    @Test func 上限を超えたら要求された週に近いものを残す() {
        var cache = MonthWeekLayoutCache(limit: 8)
        for week in 0..<8 { _ = cache.layout(at: week, stamp: Self.stamp()) { Self.layout() } }
        #expect(cache.count == 8)

        _ = cache.layout(at: 7, stamp: Self.stamp()) { Self.layout() }
        #expect(cache.count == 8)
        _ = cache.layout(at: 20, stamp: Self.stamp()) { Self.layout() }

        #expect(cache.count <= 8)
        #expect(cache.contains(20))
        #expect(cache.contains(7))
        #expect(!cache.contains(0))
    }

    @Test func 多数の週を要求しても上限を超えない() {
        var cache = MonthWeekLayoutCache(limit: 16)
        for week in 0..<200 { _ = cache.layout(at: week, stamp: Self.stamp()) { Self.layout() } }

        #expect(cache.count <= 16)
    }

    @Test func removeAllで空になり次の要求で印を取り直す() {
        var cache = MonthWeekLayoutCache()
        _ = cache.layout(at: 1, stamp: Self.stamp()) { Self.layout() }
        cache.removeAll()

        #expect(cache.count == 0)
        #expect(cache.stamp == nil)
        #expect(cache.invalidationCount == 1)
    }
}

/// ViewModel の月表示の予定の配置の記憶。
@MainActor
@Suite struct MonthWeekLayoutViewModelCacheTests {
    @Test func 同じ週を続けて読んでも配置を作り直さない() async {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3

        let first = viewModel.monthWeekLayout(at: week)
        let countAfterFirst = viewModel.monthLayoutCacheForTesting.count
        let second = viewModel.monthWeekLayout(at: week)

        #expect(first == second)
        #expect(viewModel.monthLayoutCacheForTesting.count == countAfterFirst)
        #expect(viewModel.monthLayoutCacheForTesting.contains(week))
    }

    @Test func 選択日と表示月の変化では記憶を捨てない() async {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        _ = viewModel.monthWeekLayout(at: week)
        let invalidations = viewModel.monthLayoutCacheForTesting.invalidationCount

        viewModel.select(SampleData.day(2026, 10, 20))
        viewModel.showNextMonth()
        viewModel.gridDidScroll(toTopWeek: week + 5)
        _ = viewModel.monthWeekLayout(at: week)

        #expect(viewModel.monthLayoutCacheForTesting.invalidationCount == invalidations)
        #expect(viewModel.monthLayoutCacheForTesting.contains(week))
    }

    @Test func 読み込み直すと古い配置を捨てて新しい予定で作る() async {
        let harness = Harness(events: SampleData.monthViewEvents)
        let viewModel = await harness.loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        let before = viewModel.monthWeekLayout(at: week)
        #expect(!before.items.isEmpty)
        for offset in 0..<10 { _ = viewModel.monthWeekLayout(at: week + offset) }

        viewModel.reload()
        await viewModel.waitForLoad()
        let after = viewModel.monthWeekLayout(at: week)

        #expect(viewModel.monthLayoutCacheForTesting.invalidationCount >= 1)
        #expect(viewModel.monthLayoutCacheForTesting.count == 1)
        #expect(after == before)
    }

    @Test func 日付の変化で捨てる() async {
        let harness = Harness(events: SampleData.monthViewEvents)
        let viewModel = await harness.loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        _ = viewModel.monthWeekLayout(at: week)
        let invalidations = viewModel.monthLayoutCacheForTesting.invalidationCount

        harness.dateProvider.set(SampleData.now.addingTimeInterval(24 * 60 * 60))
        viewModel.systemCalendarDidChange()
        await viewModel.waitForLoad()
        _ = viewModel.monthWeekLayout(at: week)

        #expect(viewModel.monthLayoutCacheForTesting.invalidationCount > invalidations)
    }

    @Test func 時刻が1分進むと予定が終わったかどうかを作り直す() async {
        let harness = Harness(events: SampleData.monthViewEvents)
        let viewModel = await harness.loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        _ = viewModel.monthWeekLayout(at: week)
        let invalidations = viewModel.monthLayoutCacheForTesting.invalidationCount

        harness.dateProvider.set(SampleData.now.addingTimeInterval(61))
        _ = viewModel.monthWeekLayout(at: week)

        #expect(viewModel.monthLayoutCacheForTesting.invalidationCount == invalidations + 1)
    }

    @Test func 週の開始曜日が変わると捨てる() async {
        let harness = Harness(events: SampleData.monthViewEvents)
        let viewModel = await harness.loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 3
        let before = viewModel.monthWeekLayout(at: week)
        let invalidations = viewModel.monthLayoutCacheForTesting.invalidationCount

        var calendar = SampleData.calendar
        calendar.firstWeekday = 2
        harness.dateProvider.set(calendar: calendar)
        viewModel.systemCalendarDidChange()
        await viewModel.waitForLoad()
        let after = viewModel.monthWeekLayout(at: week)

        #expect(viewModel.monthLayoutCacheForTesting.invalidationCount > invalidations)
        #expect(before != after)
    }

    @Test func 先に用意する範囲を読んでも記憶は上限を超えない() async {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let first = viewModel.displayedMonthFirstWeek

        for week in MonthPrefetch.weeks(firstVisibleWeek: first, weekCount: viewModel.weekCount) {
            _ = viewModel.monthWeekLayout(at: week)
        }
        for week in 0..<viewModel.weekCount { _ = viewModel.monthWeekLayout(at: week) }

        #expect(viewModel.monthLayoutCacheForTesting.count <= MonthWeekLayoutCache.defaultLimit)
    }

    @Test func 用意の対象は印が変わると変わり用意し済みの印は対象ごとに持つ() async {
        let viewModel = await Harness(events: SampleData.monthViewEvents).loadedPopover()
        let preparation = MonthIdlePreparation(viewModel: viewModel)
        let size = CGSize(width: 160, height: 133)

        let target = preparation.target(firstVisibleWeek: 40, size: size)
        #expect(preparation.needsWork(target))
        #expect(preparation.target(firstVisibleWeek: 41, size: size) != target)

        viewModel.reload()
        await viewModel.waitForLoad()
        #expect(preparation.target(firstVisibleWeek: 40, size: size) != target)
    }
}
