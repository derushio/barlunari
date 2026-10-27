import MenuDateDomain
import SwiftUI

/// 操作が止まっている間に先に用意する週の範囲の計算。
enum MonthPrefetch {
    /// 一番上に一部でも見えている週から数えて、見えている週の数（6 週と、一部だけ見える 1 週）。
    static let visibleWeeks = WeekTimeline.visibleWeekCount + 1
    /// 見えている週の前後に、先に用意する週の数。
    static let radius = 18

    /// 先に用意する週の番号。見えている週は含まない（描画のときに用意される）。見えている週に近い順で、後ろ（下）と前（上）を交互に並べる。
    /// 範囲は `0..<weekCount` に収める。
    static func weeks(firstVisibleWeek: Int, weekCount: Int, radius: Int = radius) -> [Int] {
        let after = firstVisibleWeek + visibleWeeks
        let before = firstVisibleWeek - 1
        var weeks: [Int] = []
        for offset in 0..<max(0, radius) {
            if (0..<weekCount).contains(after + offset) { weeks.append(after + offset) }
            if (0..<weekCount).contains(before - offset) { weeks.append(before - offset) }
        }
        return weeks
    }
}

extension MonthPrefetch {
    /// 画像を用意する週の番号。見えている週を先頭に、続けて前後の週を近い順に並べる。
    /// 見えている週にも画像が要る。表示月が変わると、月の境目の行の `Canvas` が描き直されるので、画像がないと数字を描き直すことになる。
    static func imageWeeks(firstVisibleWeek: Int, weekCount: Int, radius: Int = radius) -> [Int] {
        let visible = (firstVisibleWeek..<(firstVisibleWeek + visibleWeeks)).filter { (0..<weekCount).contains($0) }
        return visible + weeks(firstVisibleWeek: firstVisibleWeek, weekCount: weekCount, radius: radius)
    }
}

/// 月表示で、見えている週の前後の週の予定の配置と描画結果（画像）を、操作が止まっている間に先に用意する。
///
/// 日の数字と今日の印、予定のバーと文字と「他 N 件」を、週ごとに画像に描いておく（`MonthWeekImageStore`）。
/// 画像の描画は `ImageRenderer` で行い、1 回に使う時間に上限（`budget`）を設ける。超えたら続きを次の回に回す。
/// スクロールが始まったら続けない（呼ぶ側が止める）。
/// 用意した結果は画像の記憶と ViewModel の配置の記憶に入るので、スクロールで行を作るフレームは画像を貼るだけになる。
@MainActor
final class MonthIdlePreparation {
    /// 用意の対象。これが変わったら、先頭から用意し直す。
    struct Target: Hashable {
        let firstVisibleWeek: Int
        let spec: MonthWeekImageStore.Spec
        let stamp: MonthWeekLayoutCache.Stamp
        var size: CGSize { spec.size }
    }

    private let viewModel: CalendarPopoverViewModel
    private var progressTarget: Target?
    private var cursor = 0
    private var completedTarget: Target?

    init(viewModel: CalendarPopoverViewModel) {
        self.viewModel = viewModel
    }

    /// 用意の対象。外観（ライトとダーク、倍率）と行の大きさが変わると、対象も変わる。
    func target(
        firstVisibleWeek: Int, size: CGSize, colorScheme: ColorScheme = .light, displayScale: CGFloat = 2
    ) -> Target {
        Target(
            firstVisibleWeek: firstVisibleWeek,
            spec: MonthWeekImageStore.Spec(size: size, colorScheme: colorScheme, displayScale: displayScale),
            stamp: viewModel.monthLayoutStamp
        )
    }

    /// まだ用意していない週があるか。
    func needsWork(_ target: Target) -> Bool { completedTarget != target }

    /// `budget` の時間内で、用意できるだけ用意する。すべて済んだら `true` を返す。
    func prepare(_ target: Target, budget: Duration) -> Bool {
        if progressTarget != target {
            progressTarget = target
            cursor = 0
        }
        let weeks = MonthPrefetch.imageWeeks(firstVisibleWeek: target.firstVisibleWeek, weekCount: viewModel.weekCount)
        let geometry = MonthRowGeometry(size: target.size)
        let store = viewModel.monthImageStore
        let start = ContinuousClock.now
        while cursor < weeks.count {
            prepareWeek(weeks[cursor], geometry: geometry, spec: target.spec, store: store)
            cursor += 1
            if cursor < weeks.count, ContinuousClock.now - start >= budget { return false }
        }
        completedTarget = target
        return true
    }

    /// 用意した画像を捨てる。ポップオーバーが隠れたときに呼び、画像のメモリを手放す。次に表示されたとき、用意し直す。
    func releaseImages() {
        viewModel.monthImageStore.removeAll()
        progressTarget = nil
        completedTarget = nil
    }

    /// 1 週の画像を、まだなければ描く。
    func prepareWeek(_ week: Int, geometry: MonthRowGeometry, spec: MonthWeekImageStore.Spec, store: MonthWeekImageStore) {
        let days = viewModel.monthWeekDays(at: week)
        let visible = viewModel.monthWeekLayout(at: week).visible(laneCapacity: geometry.laneCapacity)
        if case .miss = store.cells(week: week, days: days, spec: spec) {
            let result = MonthWeekImageRenderer.cellsImage(days: days, spec: spec)
            store.storeCells(week: week, days: days, image: result.image, rect: result.rect, spec: spec)
        }
        if case .miss = store.events(week: week, visible: visible, spec: spec) {
            let result = MonthWeekImageRenderer.eventsImage(visible: visible, spec: spec)
            store.storeEvents(week: week, visible: visible, image: result.image, rect: result.rect, spec: spec)
        }
    }
}
