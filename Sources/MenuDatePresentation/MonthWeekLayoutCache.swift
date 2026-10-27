import MenuDateDomain

/// 月表示の週ごとの予定の配置の記憶。
///
/// 予定の配置は、週の予定、カレンダーの色、週の並び、現在時刻（予定が終わったかどうか）で決まる。
/// 行の View の body が評価されるたびに作り直すと、スクロールで行を作るフレームに載る。そこで、同じ入力のあいだは覚えておき、
/// 操作が止まっている間に、見えている週の前後の週の分を先に作っておく。
///
/// 入力が変わった（`Stamp` が変わった）ときは、覚えているものをすべて捨てる。上限を超えたら、要求された週から遠いものを捨てる。
struct MonthWeekLayoutCache {
    /// 配置の入力が変わったかどうかの印。予定の読み込み、日付の変化、週の並びの作り直し、1 分の経過で変わる。
    struct Stamp: Hashable {
        let dataRevision: Int
        let clockRevision: Int
        let timeline: WeekTimeline
        /// 現在時刻を分に丸めた値。予定が終わったかどうかが時間で変わるため。
        let minute: Int
    }

    /// 覚える週の数の上限。見えている週と前後の週と先に作る週を合わせた数より十分大きい。
    static let defaultLimit = 64

    let limit: Int
    private(set) var stamp: Stamp?
    private var layouts: [Int: MonthWeekLayout] = [:]
    /// 覚えているものを捨てた回数。
    private(set) var invalidationCount = 0

    init(limit: Int = Self.defaultLimit) {
        precondition(limit > 0, "上限は 1 以上である")
        self.limit = limit
    }

    var count: Int { layouts.count }

    func contains(_ index: Int) -> Bool { layouts[index] != nil }

    /// 番号の週の配置。印が前回と違えば、覚えているものを捨ててから作る。覚えていれば `make` を呼ばない。
    mutating func layout(at index: Int, stamp: Stamp, make: () -> MonthWeekLayout) -> MonthWeekLayout {
        if self.stamp != stamp {
            if self.stamp != nil { invalidationCount += 1 }
            layouts.removeAll(keepingCapacity: true)
            self.stamp = stamp
        }
        if let layout = layouts[index] { return layout }
        let layout = make()
        if layouts.count >= limit { evict(farthestFrom: index) }
        layouts[index] = layout
        return layout
    }

    /// 要求された週から遠い週を、上限の半分になるまで捨てる。
    private mutating func evict(farthestFrom index: Int) {
        let keep = max(1, limit / 2)
        let nearest = layouts.keys.sorted { abs($0 - index) < abs($1 - index) }.prefix(keep)
        layouts = layouts.filter { nearest.contains($0.key) }
    }

    /// 覚えているものをすべて捨てる。
    mutating func removeAll() {
        if stamp != nil { invalidationCount += 1 }
        layouts.removeAll()
        stamp = nil
    }
}
