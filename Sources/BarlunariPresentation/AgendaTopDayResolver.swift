import Foundation

/// 予定一覧の一番上の日の番号を、セクションの位置とスクロールのオフセットから求める。AppKit と SwiftUI に依存しない。
///
/// 日は、一覧の最初の日から数えた番号で表す。一番上の日は、ビューポートの上端と交わっている日である。
/// 内容の座標で、見出しを含む日のセクションの上端がオフセット以下である日のうち、最後の日を返す。
struct AgendaTopDayResolver: Equatable {
    /// 内容の座標でのセクションの上端。日の番号の昇順で、上端も昇順に並ぶ。
    private let sections: [(index: Int, top: CGFloat)]

    /// - Parameter tops: 測定済みのセクションの上端。日の番号をキーに持つ。測定していない日は、判定から外す。
    init(tops: [Int: CGFloat]) {
        sections = tops.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sections.elementsEqual(rhs.sections) { $0.index == $1.index && $0.top == $1.top }
    }

    /// 内容の座標で `offset` にあるビューポートの上端と交わっている日の番号。最初のセクションより上なら最初の日、空なら `nil`。
    func topDayIndex(at offset: CGFloat) -> Int? {
        guard let first = sections.first else { return nil }
        // 上端が offset 以下のセクションの個数を二分探索で求める。
        var low = 0
        var high = sections.count
        while low < high {
            let middle = (low + high) / 2
            if sections[middle].top <= offset { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? first.index : sections[low - 1].index
    }

    /// `offset` が、測定済みのセクションの範囲に収まっているか。収まっていなければ、測定がスクロールに追いついておらず、`topDayIndex(at:)` の結果は古い。
    ///
    /// 大きくスクロールすると、`LazyVStack` が移動先のセクションを作って測るまで、測定済みのセクションは移動前の位置のままである。
    /// 最初のセクションの上端より上は、一覧の先頭（`firstIndex`）のときだけ収まっているとみなす。最後のセクションの上端より下は、
    /// 一覧の末尾（`lastIndex`）のときだけ収まっているとみなす。
    func covers(_ offset: CGFloat, firstIndex: Int, lastIndex: Int) -> Bool {
        guard let first = sections.first, let last = sections.last else { return false }
        let aboveFirst = offset < first.top && first.index != firstIndex
        let belowLast = offset > last.top && last.index != lastIndex
        return !aboveFirst && !belowLast
    }
}
