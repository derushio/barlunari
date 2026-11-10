import CoreGraphics
import Testing

@testable import BarlunariPresentation

/// 全角の文字は 10pt、半角は 6pt の幅で、行の高さは役割ごとに決めた値にして測る。折り返しは文字単位。
@Suite struct DayBlockTextPlanTests {
    static func width(of text: String) -> CGFloat {
        text.reduce(0) { $0 + ($1.unicodeScalars.first!.value > 0x2000 ? 10 : 6) }
    }

    static func lineHeight(_ role: DayBlockTextPlan.Role) -> CGFloat {
        switch role {
        case .stackedTitle: 16
        case .time: 12
        case .lineTitle: 13
        case .tinyTitle(let size): size * 1.2
        }
    }

    static func measure(_ text: String, _ role: DayBlockTextPlan.Role, _ width: CGFloat) -> CGSize {
        var lines = 1
        var current: CGFloat = 0
        var widest: CGFloat = 0
        for character in text {
            let w = Self.width(of: String(character))
            if current + w > width, current > 0 {
                lines += 1
                widest = max(widest, current)
                current = 0
            }
            current += w
        }
        return CGSize(width: max(widest, current), height: CGFloat(lines) * Self.lineHeight(role))
    }

    static func plan(
        title: String = "確認", timeText: String = "10:45〜11:00", label: String? = nil, width: CGFloat, height: CGFloat
    ) -> DayBlockTextPlan {
        DayBlockTextPlan.make(title: title, timeText: timeText, label: label, width: width, height: height, measure: Self.measure)
    }

    // MARK: 1 行

    @Test func 一行は幅が足りれば_タイトルと開始から終了を出す() {
        let plan = Self.plan(width: 200, height: 20)
        #expect(plan.mode == .singleLine)
        #expect(plan.title == "確認")
        #expect(plan.time == "10:45〜11:00")
    }

    @Test func 一行は終了が入らなければ開始だけを出す() {
        // タイトル 20 + 間隔 6 + 開始 "10:45" 30 = 56。範囲は 6*10 ほどで入らない。
        let plan = Self.plan(width: 60, height: 20)
        #expect(plan.time == "10:45")
        #expect(plan.title == "確認")
    }

    @Test func 一行は開始も入らなければ時刻を出さずタイトルを切り詰める() {
        let plan = Self.plan(title: "とても長いタイトルの予定", width: 50, height: 20)
        #expect(plan.time == nil)
        #expect(plan.title.hasSuffix("…"))
        #expect(Self.width(of: plan.title) <= 50)
    }

    @Test func 時刻は字の途中で切らず_出すなら全体を出す() {
        for width in stride(from: 20 as CGFloat, through: 200, by: 7) {
            let plan = Self.plan(width: width, height: 20)
            if let time = plan.time {
                #expect(["10:45〜11:00", "10:45"].contains(time))
                #expect(Self.width(of: plan.title) + DayBlockTextPlan.lineGap + Self.width(of: time) <= width)
            }
        }
    }

    @Test func 開始のない時刻は終了だけの候補になる() {
        #expect(DayBlockTextPlan.timeCandidates(timeText: "〜12:00", label: nil, includesLabel: false) == ["〜12:00"])
        #expect(DayBlockTextPlan.timeCandidates(timeText: "23:00〜", label: nil, includesLabel: false) == ["23:00〜", "23:00"])
        #expect(DayBlockTextPlan.timeCandidates(timeText: "10:00〜11:00", label: "辞退", includesLabel: true)
            == ["10:00〜11:00  辞退", "10:00〜11:00", "10:00"])
    }

    // MARK: 2 行以上

    @Test func 二行以上は時刻をタイトルの下に出し_タイトルは残りの高さの行数に収める() {
        // 高さ 44: 時刻 12 を引いた 32 で、タイトルは 2 行。
        let plan = Self.plan(title: "長いタイトルの予定がここに入ります", width: 80, height: 44)
        #expect(plan.mode == .stacked)
        #expect(plan.titleLines == 2)
        #expect(plan.time == "10:45〜11:00")
        #expect(plan.title.hasSuffix("…"))
        #expect(Self.measure(plan.title, .stackedTitle, 80).height <= 32)
    }

    @Test func 二行以上で高さが足りなければタイトルは一行になる() {
        let plan = Self.plan(title: "長いタイトルの予定がここに入ります", width: 80, height: 40)
        #expect(plan.titleLines == 1)
        #expect(plan.time != nil)
        #expect(Self.measure(plan.title, .stackedTitle, 80).height <= 16)
    }

    @Test func 二行以上は時刻を範囲_開始_なしの順に選ぶ() {
        #expect(Self.plan(width: 70, height: 44).time == "10:45〜11:00")
        #expect(Self.plan(width: 40, height: 44).time == "10:45")
        let none = Self.plan(width: 20, height: 44)
        #expect(none.time == nil)
        // 時刻を出さないときは、タイトルが高さを使える。
        #expect(none.titleLines == 2)
    }

    // MARK: 高さが足りない

    @Test func 一行に満たない高さは小さい文字でタイトルだけを出す() {
        let plan = Self.plan(title: "確認の予定", width: 200, height: 10)
        #expect(plan.mode == .minimal)
        #expect(plan.time == nil)
        #expect(plan.fontSize <= 10)
        #expect(Self.lineHeight(.tinyTitle(fontSize: plan.fontSize)) <= 10)
    }

    @Test func 幅が極端に狭くても落ちない() {
        let plan = Self.plan(title: "確認", width: 0, height: 20)
        #expect(plan.time == nil)
        #expect(plan.title == "…")
    }
}
