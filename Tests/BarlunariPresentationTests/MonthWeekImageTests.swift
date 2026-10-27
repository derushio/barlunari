import CoreGraphics
import Foundation
import BarlunariDomain
import BarlunariPreviewSupport
import SwiftUI
import Testing

@testable import BarlunariPresentation

/// 月表示の行の画像の記憶と、画像にしたときの描画。
@MainActor
@Suite struct MonthWeekImageTests {
    static let size = CGSize(width: 756, height: 112)
    static let spec = MonthWeekImageStore.Spec(size: size, colorScheme: .light, displayScale: 2)

    /// 予定のある週の番号（`SampleData.denseMonthViewEvents` を読み込んだ状態で）と、その ViewModel。
    static func denseViewModel() async -> CalendarPopoverViewModel {
        await Harness(events: SampleData.denseMonthViewEvents).loadedPopover()
    }

    static func inputs(_ viewModel: CalendarPopoverViewModel, week: Int) -> (days: [MonthDayState], visible: MonthWeekLayout.Visible) {
        let geometry = MonthRowGeometry(size: size)
        return (viewModel.monthWeekDays(at: week), viewModel.monthWeekLayout(at: week).visible(laneCapacity: geometry.laneCapacity))
    }

    /// 画素の並び（RGBA、事前乗算）。
    static func pixels(of image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    /// 行の描画（マスの線、日の数字、予定）を、`store` を使って 1 枚の画像にする。
    static func renderRow(week: Int, days: [MonthDayState], visible: MonthWeekLayout.Visible, store: MonthWeekImageStore, scheme: ColorScheme = .light) -> CGImage {
        let content = Canvas { context, size in
            let geometry = MonthRowGeometry(size: size)
            MonthWeekPainter.drawCells(days, week: week, store: store, in: &context, geometry: geometry)
            MonthWeekPainter.drawGridLines(in: &context, geometry: geometry)
            MonthWeekPainter.drawEvents(visible, week: week, store: store, in: &context, geometry: geometry)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white)
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.cgImage!
    }

    // MARK: 描画

    @Test func 画像の大きさは倍率の画素で予定のある行の範囲だけを切り出す() async {
        let viewModel = await Self.denseViewModel()
        let week = viewModel.displayedMonthFirstWeek + 2
        let (days, visible) = Self.inputs(viewModel, week: week)

        let cells = MonthWeekImageRenderer.cellsImage(days: days, spec: Self.spec)
        let events = MonthWeekImageRenderer.eventsImage(visible: visible, spec: Self.spec)

        #expect(cells.rect == CGRect(x: 0, y: 0, width: 756, height: MonthRowGeometry.dayHeaderHeight))
        #expect(cells.image?.width == 1512)
        #expect(cells.image?.height == Int(MonthRowGeometry.dayHeaderHeight * 2))
        let lastLane = visible.items.map(\.lane).max() ?? 0
        #expect(events.rect.minY == MonthRowGeometry.dayHeaderHeight)
        #expect(events.rect.height <= MonthRowGeometry.laneHeight * CGFloat(lastLane + 1))
        #expect(events.image?.width == 1512)
        #expect(events.image?.height == Int(events.rect.height * 2))
    }

    @Test func 予定のない週の予定の画像はなく日の数字の画像だけある() async {
        let viewModel = await Harness(events: []).loadedPopover()
        let (days, visible) = Self.inputs(viewModel, week: viewModel.displayedMonthFirstWeek + 1)

        let events = MonthWeekImageRenderer.eventsImage(visible: visible, spec: Self.spec)
        let cells = MonthWeekImageRenderer.cellsImage(days: days, spec: Self.spec)

        #expect(events.image == nil)
        #expect(cells.image != nil)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func 画像を貼った行と描いた行は同じ画素になる(scheme: ColorScheme) async {
        let viewModel = await Self.denseViewModel()
        let spec = MonthWeekImageStore.Spec(size: Self.size, colorScheme: scheme, displayScale: 2)
        for offset in 0..<4 {
            let week = viewModel.displayedMonthFirstWeek + offset
            let (days, visible) = Self.inputs(viewModel, week: week)

            let drawn = Self.renderRow(week: week, days: days, visible: visible, store: MonthWeekImageStore(), scheme: scheme)
            let store = MonthWeekImageStore()
            let preparation = MonthIdlePreparation(viewModel: viewModel)
            preparation.prepareWeek(week, geometry: MonthRowGeometry(size: Self.size), spec: spec, store: store)
            let pasted = Self.renderRow(week: week, days: days, visible: visible, store: store, scheme: scheme)

            #expect(store.weekCount == 1)
            let lhs = Self.pixels(of: drawn)
            let rhs = Self.pixels(of: pasted)
            #expect(lhs.count == rhs.count)
            // 画像を作り直す際の丸めで、1 段階までの差は許す。
            let largest = zip(lhs, rhs).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(largest <= 2, "週 \(week) の画素の差の最大は \(largest)")
        }
    }

    // MARK: 記憶

    @Test func 同じ入力と条件なら取り出せ入力が違えば取り出せない() async {
        let viewModel = await Self.denseViewModel()
        let week = viewModel.displayedMonthFirstWeek + 2
        let (days, visible) = Self.inputs(viewModel, week: week)
        let store = MonthWeekImageStore()
        let cells = MonthWeekImageRenderer.cellsImage(days: days, spec: Self.spec)
        let events = MonthWeekImageRenderer.eventsImage(visible: visible, spec: Self.spec)
        store.storeCells(week: week, days: days, image: cells.image, rect: cells.rect, spec: Self.spec)
        store.storeEvents(week: week, visible: visible, image: events.image, rect: events.rect, spec: Self.spec)

        #expect(store.isComplete(week: week, days: days, visible: visible, spec: Self.spec))

        // 今日が変わった（日の表示内容が違う）。
        var changedDays = days
        changedDays[0] = MonthDayState(day: days[0].day, isToday: !days[0].isToday, isSelectable: days[0].isSelectable, weekdayKind: days[0].weekdayKind)
        if case .miss = store.cells(week: week, days: changedDays, spec: Self.spec) {} else { Issue.record("日の表示内容が違うのに取り出せた") }
        // 予定の配置が変わった。
        let fewer = viewModel.monthWeekLayout(at: week).visible(laneCapacity: 1)
        #expect(fewer != visible)
        if case .miss = store.events(week: week, visible: fewer, spec: Self.spec) {} else { Issue.record("予定の配置が違うのに取り出せた") }
        // 別の週。
        if case .miss = store.cells(week: week + 1, days: days, spec: Self.spec) {} else { Issue.record("別の週で取り出せた") }
    }

    @Test func 外観と倍率と行の大きさが変わると記憶していた画像をすべて捨てる() async {
        let viewModel = await Self.denseViewModel()
        let week = viewModel.displayedMonthFirstWeek + 2
        let (days, visible) = Self.inputs(viewModel, week: week)
        let store = MonthWeekImageStore()
        let geometry = MonthRowGeometry(size: Self.size)
        let preparation = MonthIdlePreparation(viewModel: viewModel)
        for neighbor in 0..<3 { preparation.prepareWeek(week + neighbor, geometry: geometry, spec: Self.spec, store: store) }
        #expect(store.weekCount == 3)

        let dark = MonthWeekImageStore.Spec(size: Self.size, colorScheme: .dark, displayScale: 2)
        #expect(!store.isComplete(week: week, days: days, visible: visible, spec: dark))
        let retina3 = MonthWeekImageStore.Spec(size: Self.size, colorScheme: .light, displayScale: 3)
        #expect(!store.isComplete(week: week, days: days, visible: visible, spec: retina3))
        let narrower = MonthWeekImageStore.Spec(size: CGSize(width: 700, height: 112), colorScheme: .light, displayScale: 2)
        #expect(!store.isComplete(week: week, days: days, visible: visible, spec: narrower))
        // 取り出しだけでは捨てない。違う条件で記憶したときに、すべて捨てる。
        #expect(store.weekCount == 3)
        preparation.prepareWeek(week, geometry: geometry, spec: dark, store: store)
        #expect(store.weekCount == 1)
        #expect(store.resetCount == 1)
    }

    @Test func メモリが上限を超えたら要求された週から遠い週を捨てる() async {
        let viewModel = await Self.denseViewModel()
        let first = viewModel.displayedMonthFirstWeek
        let geometry = MonthRowGeometry(size: Self.size)
        let preparation = MonthIdlePreparation(viewModel: viewModel)
        let unlimited = MonthWeekImageStore()
        preparation.prepareWeek(first + 2, geometry: geometry, spec: Self.spec, store: unlimited)
        let perWeek = unlimited.byteCount
        #expect(perWeek > 0)

        let store = MonthWeekImageStore(byteLimit: perWeek * 3)
        for week in [first + 2, first + 3, first + 4, first + 5, first + 6] {
            preparation.prepareWeek(week, geometry: geometry, spec: Self.spec, store: store)
        }

        #expect(store.byteCount <= perWeek * 3 + perWeek / 2)
        #expect(store.weekCount <= 4)
        // 最後に記憶した週は残り、最初に記憶した遠い週から捨てられる。
        #expect(store.weeks.contains(first + 6))
        #expect(!store.weeks.contains(first + 2))
        #expect(store.evictionCount >= 1)
    }

    @Test func 既定の範囲の画像のメモリは上限に収まる() async {
        let viewModel = await Self.denseViewModel()
        let first = viewModel.displayedMonthFirstWeek
        let store = viewModel.monthImageStore
        let geometry = MonthRowGeometry(size: Self.size)
        let preparation = MonthIdlePreparation(viewModel: viewModel)
        let weeks = MonthPrefetch.imageWeeks(firstVisibleWeek: first, weekCount: viewModel.weekCount)
        for week in weeks { preparation.prepareWeek(week, geometry: geometry, spec: Self.spec, store: store) }

        #expect(store.weekCount == weeks.count)
        #expect(store.byteCount <= store.byteLimit)
        #expect(store.evictionCount == 0)
        print("画像の記憶: \(weeks.count) 週、\(store.byteCount / 1024) KiB、1 週あたり \(store.byteCount / weeks.count / 1024) KiB")
    }

    // MARK: 無効化

    @Test func 予定を読み込み直すと画像を捨てる() async {
        let viewModel = await Self.denseViewModel()
        let week = viewModel.displayedMonthFirstWeek + 2
        MonthIdlePreparation(viewModel: viewModel).prepareWeek(
            week, geometry: MonthRowGeometry(size: Self.size), spec: Self.spec, store: viewModel.monthImageStore
        )
        #expect(viewModel.monthImageStore.weekCount == 1)

        viewModel.reload()
        await viewModel.waitForLoad()

        #expect(viewModel.monthImageStore.weekCount == 0)
    }

    @Test func 日付が変わると画像を捨てる() async {
        let harness = Harness(events: SampleData.denseMonthViewEvents)
        let viewModel = await harness.loadedPopover()
        let week = viewModel.displayedMonthFirstWeek + 2
        MonthIdlePreparation(viewModel: viewModel).prepareWeek(
            week, geometry: MonthRowGeometry(size: Self.size), spec: Self.spec, store: viewModel.monthImageStore
        )
        #expect(viewModel.monthImageStore.weekCount == 1)

        harness.dateProvider.set(SampleData.now.addingTimeInterval(24 * 60 * 60))
        viewModel.systemCalendarDidChange()
        await viewModel.waitForLoad()

        #expect(viewModel.monthImageStore.weekCount == 0)
    }

    @Test func 表示月と選択日が変わっても画像は捨てない() async {
        let viewModel = await Self.denseViewModel()
        let week = viewModel.displayedMonthFirstWeek + 2
        MonthIdlePreparation(viewModel: viewModel).prepareWeek(
            week, geometry: MonthRowGeometry(size: Self.size), spec: Self.spec, store: viewModel.monthImageStore
        )

        viewModel.select(SampleData.day(2026, 10, 20))
        viewModel.showNextMonth()
        viewModel.gridDidScroll(toTopWeek: week + 5)

        let (days, visible) = Self.inputs(viewModel, week: week)
        #expect(viewModel.monthImageStore.isComplete(week: week, days: days, visible: visible, spec: Self.spec))
    }

    // MARK: 用意

    @Test func 用意は見えている週を先頭に前後の週を近い順に並べる() {
        let weeks = MonthPrefetch.imageWeeks(firstVisibleWeek: 50, weekCount: 105, radius: 2)

        #expect(weeks == [50, 51, 52, 53, 54, 55, 56, 57, 49, 58, 48])
    }

    @Test func 用意は範囲の画像を揃え一度済んだら対象が変わるまで要らない() async {
        let viewModel = await Self.denseViewModel()
        let preparation = MonthIdlePreparation(viewModel: viewModel)
        let first = viewModel.displayedMonthFirstWeek
        let target = preparation.target(firstVisibleWeek: first, size: Self.size, colorScheme: .light, displayScale: 2)
        #expect(preparation.needsWork(target))

        var rounds = 0
        while !preparation.prepare(target, budget: .zero) { rounds += 1 }

        #expect(rounds > 0)
        #expect(!preparation.needsWork(target))
        let weeks = MonthPrefetch.imageWeeks(firstVisibleWeek: first, weekCount: viewModel.weekCount)
        #expect(viewModel.monthImageStore.weekCount == weeks.count)
        #expect(preparation.needsWork(preparation.target(firstVisibleWeek: first, size: Self.size, colorScheme: .dark, displayScale: 2)))
        #expect(preparation.needsWork(preparation.target(firstVisibleWeek: first, size: Self.size, colorScheme: .light, displayScale: 1)))
        #expect(preparation.needsWork(preparation.target(firstVisibleWeek: first + 1, size: Self.size, colorScheme: .light, displayScale: 2)))
    }

    // MARK: 覆い

    @Test func 覆いの列は先頭から続く列と末尾まで続く列に分かれる() async {
        let viewModel = await Self.denseViewModel()
        for week in 0..<viewModel.weekCount {
            let columns = viewModel.outOfMonthColumns(inWeek: week)
            let outside = MonthWeekShade.Outside(columns: columns)
            #expect(outside.columns == columns, "週 \(week)")
        }
        #expect(MonthWeekShade.Outside(columns: []).columns == [])
        #expect(MonthWeekShade.Outside(columns: Array(0..<7)).leading == 7)
        #expect(MonthWeekShade.Outside(columns: [0, 1, 2]) == MonthWeekShade.Outside(columns: [0, 1, 2]))
        #expect(MonthWeekShade.Outside(columns: [5, 6]).trailing == 2)
    }
}
