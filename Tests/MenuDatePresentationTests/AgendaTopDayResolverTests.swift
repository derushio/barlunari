import Foundation
import Testing

@testable import MenuDatePresentation

@Suite struct AgendaTopDayResolverTests {
    static let day1 = 3_640
    static let day2 = 3_641
    static let day3 = 3_642

    /// 3 つのセクションを、上端 0、100、250 に置く。
    func resolver() -> AgendaTopDayResolver {
        AgendaTopDayResolver(tops: [Self.day1: 0, Self.day2: 100, Self.day3: 250])
    }

    @Test func セクションの内側のオフセットは_そのセクションの日を返す() {
        #expect(resolver().topDayIndex(at: 50) == Self.day1)
        #expect(resolver().topDayIndex(at: 180) == Self.day2)
    }

    @Test func オフセットがちょうどセクションの上端なら_そのセクションの日を返す() {
        #expect(resolver().topDayIndex(at: 100) == Self.day2)
        #expect(resolver().topDayIndex(at: 250) == Self.day3)
    }

    @Test func オフセットがセクションの上端の直前なら_前のセクションの日を返す() {
        #expect(resolver().topDayIndex(at: 99.5) == Self.day1)
        #expect(resolver().topDayIndex(at: 249) == Self.day2)
    }

    @Test func 最初のセクションより上なら_最初の日を返す() {
        #expect(resolver().topDayIndex(at: -40) == Self.day1)
    }

    @Test func 最後のセクションより下なら_最後の日を返す() {
        #expect(resolver().topDayIndex(at: 10_000) == Self.day3)
    }

    @Test func 空なら_nil() {
        #expect(AgendaTopDayResolver(tops: [:]).topDayIndex(at: 0) == nil)
    }

    @Test func 測定していないセクションは_判定から外す() {
        let partial = AgendaTopDayResolver(tops: [Self.day1: 0, Self.day3: 250])

        #expect(partial.topDayIndex(at: 120) == Self.day1)
        #expect(partial.topDayIndex(at: 260) == Self.day3)
    }

    @Test func 内容の座標が大きくずれていても_オフセットに対応する日を返す() {
        let shifted = AgendaTopDayResolver(tops: [Self.day1: 300_000, Self.day2: 300_100, Self.day3: 300_250])

        #expect(shifted.topDayIndex(at: 300_110) == Self.day2)
    }

    @Test func 測定した順序によらず_日の番号の昇順で判定する() {
        let resolver = AgendaTopDayResolver(tops: [Self.day3: 250, Self.day1: 0, Self.day2: 100])

        #expect(resolver == self.resolver())
    }
}

/// 測定がスクロールに追いついているかの判定。
@Suite struct AgendaTopDayResolverCoverageTests {
    /// 日の番号 3_640〜3_642 を測った状態。上端は 0、100、250。
    func resolver() -> AgendaTopDayResolver {
        AgendaTopDayResolver(tops: [3_640: 0, 3_641: 100, 3_642: 250])
    }

    func covers(_ offset: CGFloat, resolver: AgendaTopDayResolver, firstIndex: Int = 0, lastIndex: Int = 7_286) -> Bool {
        resolver.covers(offset, firstIndex: firstIndex, lastIndex: lastIndex)
    }

    @Test func 測定したセクションの範囲に収まるオフセットは収まっているとみなす() {
        #expect(covers(0, resolver: resolver()))
        #expect(covers(180, resolver: resolver()))
        #expect(covers(250, resolver: resolver()))
    }

    @Test func 測定したセクションより離れたオフセットは追いついていないとみなす() {
        // 大きくスクロールして、移動先のセクションがまだ測られていない。
        #expect(!covers(-1, resolver: resolver()))
        #expect(!covers(251, resolver: resolver()))
        #expect(!covers(20_000, resolver: resolver()))
    }

    @Test func 一覧の先頭と末尾では範囲の外側も収まっているとみなす() {
        let first = AgendaTopDayResolver(tops: [0: 0, 1: 100])
        #expect(covers(-30, resolver: first))
        let last = AgendaTopDayResolver(tops: [7_285: 0, 7_286: 100])
        #expect(covers(180, resolver: last))
    }

    @Test func 測定したセクションがないときは追いついていないとみなす() {
        #expect(!covers(0, resolver: AgendaTopDayResolver(tops: [:])))
    }
}
