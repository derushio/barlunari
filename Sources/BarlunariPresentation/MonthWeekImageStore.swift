import CoreGraphics
import BarlunariDomain
import SwiftUI
import Synchronization

/// 月表示の 1 週の行の描画結果（画像）の記憶。
///
/// 日の数字と今日の印（マスの層）と、予定のバーと文字と「他 N 件」（予定の層）を、それぞれ 1 枚の画像に描いておく。
/// 行の `Canvas` は、画像があれば貼るだけで済み、文字の解決と図形の描画をスクロールで行を作るフレームでしなくてよい。
///
/// 画像は、描いたときの入力（日の表示内容、予定の配置）と、描いた条件（行の大きさ、ライトとダーク、倍率）を一緒に覚える。
/// 取り出すときに今の入力と条件が同じかを比べ、違えば無かったことにする。予定の読み込み、日付の変化、外観・倍率・行の大きさの変化は、
/// 入力か条件が変わるので、古い画像が使われることはない。条件が変わったときは、記憶している画像をすべて捨てる。
///
/// メモリには上限（`byteLimit`）を設ける。超えたら、要求された週から遠い週の画像から捨てる。
/// `Canvas` の描画は別のスレッドで行われうるので、`Mutex` で守る。
final class MonthWeekImageStore: Sendable {
    /// 画像を描いたときの条件。変わったら、記憶している画像をすべて捨てる。
    struct Spec: Hashable, Sendable {
        let size: CGSize
        let colorScheme: ColorScheme
        /// 倍率を 100 倍した整数。
        let displayScale: Int

        init(size: CGSize, colorScheme: ColorScheme, displayScale: CGFloat) {
            self.size = size
            self.colorScheme = colorScheme
            self.displayScale = Int((displayScale * 100).rounded())
        }

        var scale: CGFloat { CGFloat(displayScale) / 100 }
    }

    /// 取り出した結果。
    enum Lookup {
        /// 覚えていない、または入力が今と違う。
        case miss
        /// 描くものがない（その週に予定がない）。
        case empty
        /// 貼る画像と、行の座標での位置。
        case image(CGImage, rect: CGRect)
    }

    /// 1 枚の画像と、描いたときの入力。
    private struct Layer<Input: Equatable & Sendable>: Sendable {
        let input: Input
        /// 描くものがなければ `nil`。
        let image: CGImage?
        let rect: CGRect
        var bytes: Int { image.map { $0.bytesPerRow * $0.height } ?? 0 }
    }

    private struct Entry: Sendable {
        var cells: Layer<[MonthDayState]>?
        var events: Layer<MonthWeekLayout.Visible>?
        var bytes: Int { (cells?.bytes ?? 0) + (events?.bytes ?? 0) }
    }

    private struct State: Sendable {
        var spec: Spec?
        var entries: [Int: Entry] = [:]
        var bytes = 0
        var evictionCount = 0
        var resetCount = 0
    }

    /// 既定のメモリの上限。
    static let defaultByteLimit = 64 * 1024 * 1024

    let byteLimit: Int
    private let state = Mutex(State())

    init(byteLimit: Int = MonthWeekImageStore.defaultByteLimit) {
        precondition(byteLimit > 0, "上限は 1 以上である")
        self.byteLimit = byteLimit
    }

    // MARK: 取り出し

    func cells(week: Int, days: [MonthDayState], spec: Spec) -> Lookup {
        state.withLock { state in
            guard state.spec == spec, let layer = state.entries[week]?.cells, layer.input == days else { return .miss }
            guard let image = layer.image else { return .empty }
            return .image(image, rect: layer.rect)
        }
    }

    func events(week: Int, visible: MonthWeekLayout.Visible, spec: Spec) -> Lookup {
        state.withLock { state in
            guard state.spec == spec, let layer = state.entries[week]?.events, layer.input == visible else { return .miss }
            guard let image = layer.image else { return .empty }
            return .image(image, rect: layer.rect)
        }
    }

    /// 週の画像が今の入力と条件で揃っているか。
    func isComplete(week: Int, days: [MonthDayState], visible: MonthWeekLayout.Visible, spec: Spec) -> Bool {
        if case .miss = cells(week: week, days: days, spec: spec) { return false }
        if case .miss = events(week: week, visible: visible, spec: spec) { return false }
        return true
    }

    // MARK: 記憶

    func storeCells(week: Int, days: [MonthDayState], image: CGImage?, rect: CGRect, spec: Spec) {
        store(week: week, spec: spec) { $0.cells = Layer(input: days, image: image, rect: rect) }
    }

    func storeEvents(week: Int, visible: MonthWeekLayout.Visible, image: CGImage?, rect: CGRect, spec: Spec) {
        store(week: week, spec: spec) { $0.events = Layer(input: visible, image: image, rect: rect) }
    }

    private func store(week: Int, spec: Spec, update: (inout Entry) -> Void) {
        state.withLock { state in
            if state.spec != spec {
                if state.spec != nil { state.resetCount += 1 }
                state.entries.removeAll(keepingCapacity: true)
                state.bytes = 0
                state.spec = spec
            }
            var entry = state.entries[week] ?? Entry()
            state.bytes -= entry.bytes
            update(&entry)
            state.bytes += entry.bytes
            state.entries[week] = entry
            // 上限を超えたら、要求された週から遠い週を捨てる。要求された週は残す。
            while state.bytes > byteLimit, let farthest = state.entries.keys.filter({ $0 != week }).max(by: { abs($0 - week) < abs($1 - week) }) {
                state.bytes -= state.entries[farthest]?.bytes ?? 0
                state.entries[farthest] = nil
                state.evictionCount += 1
            }
        }
    }

    /// 記憶している画像をすべて捨てる。予定の読み込みと日付の変化で呼ぶ。
    func removeAll() {
        state.withLock { state in
            if !state.entries.isEmpty { state.resetCount += 1 }
            state.entries.removeAll()
            state.bytes = 0
        }
    }

    // MARK: 状態（テストと報告用）

    var weekCount: Int { state.withLock { $0.entries.count } }
    var byteCount: Int { state.withLock { $0.bytes } }
    var evictionCount: Int { state.withLock { $0.evictionCount } }
    var resetCount: Int { state.withLock { $0.resetCount } }
    var weeks: [Int] { state.withLock { $0.entries.keys.sorted() } }
}
