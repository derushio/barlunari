import BarlunariDomain
import Foundation
import Testing

@testable import BarlunariPresentation

/// パレットの読みやすさ（WCAG 2.2 のコントラスト比）と、カレンダーの色の割り当て。
@Suite struct CalendarPaletteTests {
    // MARK: 基準

    /// ウインドウの背景の最も明るい側と暗い側。どちらに対しても基準を満たす。
    static let lightBackgrounds: [UInt32] = [0xFFFFFF, 0xECECEC]
    static let darkBackgrounds: [UInt32] = [0x1E1E1E, 0x323232]
    /// 標準の文字色（`.primary`）を、不透明度を含めて背景に重ねたときの最も薄い側の値。
    static let lightText: UInt32 = 0x262626
    static let darkText: UInt32 = 0xE6E6E6

    struct Case: Sendable, CustomTestStringConvertible {
        let color: PaletteColor
        let isDark: Bool
        var roles: PaletteRoles { color.roles(isDark: isDark) }
        var backgrounds: [UInt32] { isDark ? CalendarPaletteTests.darkBackgrounds : CalendarPaletteTests.lightBackgrounds }
        var text: UInt32 { isDark ? CalendarPaletteTests.darkText : CalendarPaletteTests.lightText }
        var testDescription: String { "\(color.name) \(isDark ? "dark" : "light")" }
    }

    static let cases: [Case] = CalendarPalette.all.flatMap { [Case(color: $0, isDark: false), Case(color: $0, isDark: true)] }

    // MARK: 数と重複

    @Test func 三十二色以上あり有彩色が二十六色以上で低彩度の系統もある() {
        let all = CalendarPalette.all
        #expect(all.count >= 32)
        #expect(all.filter { $0.family == .chromatic }.count >= 26)
        #expect(all.contains { $0.family == .neutral })
        #expect(all.contains { $0.family == .earth })
    }

    @Test func 名前と色が重複しない() {
        let all = CalendarPalette.all
        #expect(Set(all.map(\.name)).count == all.count)
        for isDark in [false, true] {
            #expect(Set(all.map { $0.roles(isDark: isDark).fill }).count == all.count)
            #expect(Set(all.map { $0.roles(isDark: isDark).accent }).count == all.count)
            #expect(Set(all.map { $0.roles(isDark: isDark).tint }).count == all.count)
        }
        #expect(Set(all.map(\.reference)).count == all.count)
    }

    // MARK: コントラスト比

    @Test(arguments: cases) func 塗りの上の文字は四・五対一以上(_ c: Case) {
        #expect(Contrast.ratio(c.roles.onFill, c.roles.fill) >= 4.5)
        #expect([0xFFFFFF, 0x141414].contains(c.roles.onFill))
    }

    @Test(arguments: cases) func 薄い背景の上の標準の文字は四・五対一以上(_ c: Case) {
        #expect(Contrast.ratio(c.text, c.roles.tint) >= 4.5)
        #expect(Contrast.ratio(c.text, c.roles.selectedTint) >= 4.5)
    }

    @Test(arguments: cases) func 点と線はウインドウの背景に対して三対一以上(_ c: Case) {
        for background in c.backgrounds {
            #expect(Contrast.ratio(c.roles.accent, background) >= 3)
        }
    }

    @Test(arguments: cases) func 過去の予定の点と線は不透明度をかけても三対一以上(_ c: Case) {
        for background in c.backgrounds {
            let faded = Contrast.blend(c.roles.accent, over: background, opacity: CalendarPalette.pastOpacity)
            #expect(Contrast.ratio(faded, Contrast.rgb(background)) >= 3)
        }
    }

    @Test(arguments: cases) func 過去の予定の帯の文字は不透明度をかけても塗りに対して三対一以上で標準の文字も読める(_ c: Case) {
        for background in c.backgrounds {
            let fill = Contrast.blend(c.roles.fill, over: background, opacity: CalendarPalette.pastOpacity)
            let onFill = Contrast.blend(c.roles.onFill, over: background, opacity: CalendarPalette.pastOpacity)
            #expect(Contrast.ratio(onFill, fill) >= 3)
            let text = Contrast.blend(c.text, over: background, opacity: CalendarPalette.pastOpacity)
            #expect(Contrast.ratio(text, Contrast.rgb(background)) >= 3)
        }
    }

    // MARK: 割り当て

    private func assigned(_ hex: String) throws -> String {
        CalendarPalette.color(for: try CalendarColor(hex: hex)).name
    }

    /// macOS のカレンダーの既定色と、Google カレンダーの色が、想定した系統に割り当たる。
    @Test(arguments: [
        ("#FF2968", "macOS 赤", ["Ruby", "Crimson", "Coral"]),
        ("#FF9500", "macOS オレンジ", ["Orange", "Tangerine", "Vermilion"]),
        ("#FFCC00", "macOS 黄", ["Amber", "Yellow"]),
        ("#63DA38", "macOS 緑", ["Lime", "Chartreuse", "Green", "Grass"]),
        ("#1BADF8", "macOS 青", ["Sky", "Azure", "Blue"]),
        ("#CC73E1", "macOS 紫", ["Purple", "Orchid", "Violet"]),
        ("#A2845E", "macOS 茶", ["Brown", "Bronze", "Taupe", "Sand"]),
        ("#D50000", "Tomato", ["Tomato", "Ruby", "Crimson", "Vermilion"]),
        ("#E67C73", "Flamingo", ["Coral", "Tomato", "Crimson"]),
        ("#F4511E", "Tangerine", ["Vermilion", "Tomato", "Orange"]),
        ("#F6BF26", "Banana", ["Amber", "Yellow"]),
        ("#33B679", "Sage", ["Grass", "Emerald", "Green", "Jade"]),
        ("#0B8043", "Basil", ["Green", "Grass", "Emerald"]),
        ("#039BE5", "Peacock", ["Azure", "Sky", "Blue"]),
        ("#3F51B5", "Blueberry", ["Indigo", "Cobalt", "Iris"]),
        ("#7986CB", "Lavender", ["Indigo", "Iris", "Cobalt"]),
        ("#8E24AA", "Grape", ["Purple", "Orchid", "Violet"]),
        ("#616161", "Graphite", ["Graphite"]),
        // 明度の違う色も、色相が同じ系統に割り当たる。
        ("#1A237E", "暗い紺", ["Indigo", "Cobalt", "Blue"]),
        ("#B3E5FC", "薄い水色", ["Sky", "Cyan", "Azure"]),
        ("#1B5E20", "暗い緑", ["Green", "Grass", "Emerald"]),
        ("#F48FB1", "薄いピンク", ["Pink", "Magenta", "Ruby", "Crimson"]),
        // 彩度の低い色は灰色の系統に割り当たる。
        ("#808080", "灰色", ["Graphite", "Stone"]),
        ("#607D8B", "青みの灰色", ["Slate"]),
    ] as [(String, String, [String])])
    func 代表的なカレンダーの色が想定した系統に割り当たる(hex: String, label: String, expected: [String]) throws {
        let name = try assigned(hex)
        #expect(expected.contains(name), "\(label) \(hex) は \(name) に割り当たった")
    }

    @Test func 彩度の低い色は灰色の系統にだけ割り当たり有彩色は灰色の系統に割り当たらない() throws {
        for hex in ["#000000", "#FFFFFF", "#808080", "#8A8A90", "#7A7A78"] {
            let color = CalendarPalette.color(for: try CalendarColor(hex: hex))
            #expect(color.family == .neutral, "\(hex) は \(color.name)")
        }
        for hex in ["#FF0000", "#00FF00", "#0000FF", "#FFCC00", "#1A237E", "#B3E5FC"] {
            let color = CalendarPalette.color(for: try CalendarColor(hex: hex))
            #expect(color.family != .neutral, "\(hex) は \(color.name)")
        }
    }

    @Test func 同じ色には記憶した同じ割り当てを返す() throws {
        let color = try CalendarColor(hex: "#3F51B5")
        let first = CalendarPalette.color(for: color)
        #expect(CalendarPalette.color(for: color) == first)
        #expect(first == CalendarPalette.all[CalendarPalette.nearestIndex(to: color)])
    }

    @Test func パレットの基準の色は自分自身に割り当たる() {
        for color in CalendarPalette.all {
            let hex = color.reference
            let calendarColor = CalendarColor(red: UInt8(hex >> 16 & 0xFF), green: UInt8(hex >> 8 & 0xFF), blue: UInt8(hex & 0xFF))
            #expect(CalendarPalette.color(for: calendarColor).name == color.name)
        }
    }
}

/// WCAG 2.2 の相対輝度とコントラスト比。
enum Contrast {
    typealias RGB = (r: Double, g: Double, b: Double)

    static func rgb(_ hex: UInt32) -> RGB {
        (Double(hex >> 16 & 0xFF), Double(hex >> 8 & 0xFF), Double(hex & 0xFF))
    }

    static func luminance(_ color: RGB) -> Double {
        func linear(_ value: Double) -> Double {
            let c = value / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func ratio(_ a: UInt32, _ b: UInt32) -> Double { ratio(rgb(a), rgb(b)) }

    /// `color` を、不透明度 `opacity` で `background` の上に重ねた色。
    static func blend(_ color: UInt32, over background: UInt32, opacity: Double) -> RGB {
        let (f, b) = (rgb(color), rgb(background))
        return (opacity * f.r + (1 - opacity) * b.r, opacity * f.g + (1 - opacity) * b.g, opacity * f.b + (1 - opacity) * b.b)
    }
}
