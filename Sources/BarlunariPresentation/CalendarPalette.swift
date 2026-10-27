import BarlunariDomain
import Foundation
import Synchronization

/// パレットの系統。割り当てで、彩度の低い色を灰色の系統へ寄せるために使う。
public enum PaletteFamily: Sendable, Equatable {
    /// 色相で区別する有彩色。
    case chromatic
    /// 彩度の低い灰色の系統。
    case neutral
    /// 茶色、砂色のような、彩度が低く色相のある系統。
    case earth
}

/// 外観ごとの、役割別の色。値は `0xRRGGBB` の sRGB である。
public struct PaletteRoles: Sendable, Equatable {
    /// 塗り。月表示の終日の帯と色見本に使う。
    public let fill: UInt32
    /// 塗りの上の文字。白か黒に近い色のうち、塗りに対して 4.5:1 以上になる方である。
    public let onFill: UInt32
    /// 薄い背景。日の欄のブロックの背景で、標準の文字色が 4.5:1 以上で読める。
    public let tint: UInt32
    /// 詳細を開いている予定の薄い背景。`tint` より濃い。
    public let selectedTint: UInt32
    /// 点と線。点、左端の線、枠線、一覧の線に使う。その外観のウインドウの背景に対して 3:1 以上である。
    public let accent: UInt32

    init(fill: UInt32, onFill: UInt32, tint: UInt32, selectedTint: UInt32, accent: UInt32) {
        self.fill = fill
        self.onFill = onFill
        self.tint = tint
        self.selectedTint = selectedTint
        self.accent = accent
    }
}

/// パレットの色 1 つ。名前、系統、割り当ての基準になる色、ライトとダークの役割別の色を持つ。
public struct PaletteColor: Sendable, Equatable {
    public let name: String
    public let family: PaletteFamily
    /// 割り当てで、カレンダーの色との近さを測る基準の色。
    public let reference: UInt32
    public let light: PaletteRoles
    public let dark: PaletteRoles

    public func roles(isDark: Bool) -> PaletteRoles { isDark ? dark : light }
}

/// カレンダーの色を、見やすく作ったパレットの色に割り当てる。
///
/// 値は OKLCH で作り、sRGB に収まる最大の彩度に切り詰めて、16 進の固定値にした。
/// 色相ごとに、ライトは塗りを白か黒に近い文字が 4.5:1 以上になる明度、点と線をウインドウの背景に 3:1 以上になる明度に置く。
/// ダークは塗りと点を明るく置き、隣り合う色相は明度を交互にずらして区別しやすくした。
public enum CalendarPalette {
    /// 過去の予定の点と線を描くときの不透明度。点と線がこの値でもウインドウの背景に対して 3:1 以上を保つ。
    public static let pastOpacity: Double = 0.85
    /// 過去の予定の文字と薄い背景を描くときの不透明度。標準の文字色がこの値でも背景に対して 4.5:1 以上を保つ。
    public static let pastTextOpacity: Double = 0.7

    /// パレットの全色。有彩色、灰色の系統、茶色などの順に並ぶ。
    public static let all: [PaletteColor] = [
        PaletteColor(
            name: "Ruby", family: .chromatic, reference: 0xD46784,
            light: PaletteRoles(fill: 0xD0386C, onFill: 0xFFFFFF, tint: 0xFFE8EC, selectedTint: 0xFFD0D9, accent: 0xCE4972),
            dark: PaletteRoles(fill: 0xFF85A4, onFill: 0x141414, tint: 0x42232A, selectedTint: 0x62313D, accent: 0xE25C83)
        ),
        PaletteColor(
            name: "Crimson", family: .chromatic, reference: 0xD66775,
            light: PaletteRoles(fill: 0xD23857, onFill: 0xFFFFFF, tint: 0xFFE8E9, selectedTint: 0xFFD1D3, accent: 0xBE3851),
            dark: PaletteRoles(fill: 0xFA7687, onFill: 0x141414, tint: 0x432326, selectedTint: 0x633137, accent: 0xF66C7F)
        ),
        PaletteColor(
            name: "Coral", family: .chromatic, reference: 0xD76868,
            light: PaletteRoles(fill: 0xD33944, onFill: 0xFFFFFF, tint: 0xFFE8E7, selectedTint: 0xFFD1CF, accent: 0xD14A4F),
            dark: PaletteRoles(fill: 0xFF8987, onFill: 0x141414, tint: 0x432423, selectedTint: 0x633231, accent: 0xE55D60)
        ),
        PaletteColor(
            name: "Tomato", family: .chromatic, reference: 0xD76A58,
            light: PaletteRoles(fill: 0xD23C28, onFill: 0xFFFFFF, tint: 0xFFE9E4, selectedTint: 0xFFD2C9, accent: 0xBF3D2A),
            dark: PaletteRoles(fill: 0xFB7A65, onFill: 0x141414, tint: 0x43241F, selectedTint: 0x63322A, accent: 0xF7705A)
        ),
        PaletteColor(
            name: "Vermilion", family: .chromatic, reference: 0xD56E47,
            light: PaletteRoles(fill: 0xCA4800, onFill: 0xFFFFFF, tint: 0xFFE9E1, selectedTint: 0xFFD3C3, accent: 0xCD5119),
            dark: PaletteRoles(fill: 0xFF8E63, onFill: 0x141414, tint: 0x42251A, selectedTint: 0x623423, accent: 0xE26431)
        ),
        PaletteColor(
            name: "Orange", family: .chromatic, reference: 0xD07431,
            light: PaletteRoles(fill: 0xF07800, onFill: 0x141414, tint: 0xFFEADD, selectedTint: 0xFFD4BA, accent: 0xA75200),
            dark: PaletteRoles(fill: 0xF38533, onFill: 0x141414, tint: 0x412716, selectedTint: 0x60361A, accent: 0xED7A19)
        ),
        PaletteColor(
            name: "Tangerine", family: .chromatic, reference: 0xC87B13,
            light: PaletteRoles(fill: 0xFE9B00, onFill: 0x141414, tint: 0xFFEBD7, selectedTint: 0xFCD6B2, accent: 0xAB6700),
            dark: PaletteRoles(fill: 0xF59920, onFill: 0x141414, tint: 0x3E2912, selectedTint: 0x5C3A12, accent: 0xC57700)
        ),
        PaletteColor(
            name: "Amber", family: .chromatic, reference: 0xBA8400,
            light: PaletteRoles(fill: 0xF3AE00, onFill: 0x141414, tint: 0xFDECD1, selectedTint: 0xF5DAAF, accent: 0x896100),
            dark: PaletteRoles(fill: 0xD79A00, onFill: 0x141414, tint: 0x3A2B0F, selectedTint: 0x563D0B, accent: 0xC78E00)
        ),
        PaletteColor(
            name: "Yellow", family: .chromatic, reference: 0xAA8D00,
            light: PaletteRoles(fill: 0xFFD400, onFill: 0x141414, tint: 0xF7EFD1, selectedTint: 0xECDEAE, accent: 0x8C7300),
            dark: PaletteRoles(fill: 0xD2AE00, onFill: 0x141414, tint: 0x362D0E, selectedTint: 0x4F410A, accent: 0xA38700)
        ),
        PaletteColor(
            name: "Citron", family: .chromatic, reference: 0x9B9300,
            light: PaletteRoles(fill: 0xF3E81C, onFill: 0x141414, tint: 0xF1F1D2, selectedTint: 0xE3E1B0, accent: 0x6F6900),
            dark: PaletteRoles(fill: 0xB4AB00, onFill: 0x141414, tint: 0x312F10, selectedTint: 0x48440E, accent: 0xA39B00)
        ),
        PaletteColor(
            name: "Lime", family: .chromatic, reference: 0x859B26,
            light: PaletteRoles(fill: 0xDAFB54, onFill: 0x141414, tint: 0xEBF3D5, selectedTint: 0xD8E5B6, accent: 0x6A7E00),
            dark: PaletteRoles(fill: 0xA4BF34, onFill: 0x141414, tint: 0x2B3114, selectedTint: 0x3E4817, accent: 0x7C9300)
        ),
        PaletteColor(
            name: "Chartreuse", family: .chromatic, reference: 0x6CA140,
            light: PaletteRoles(fill: 0xA1EE60, onFill: 0x141414, tint: 0xE4F5DA, selectedTint: 0xCEE8BD, accent: 0x417400),
            dark: PaletteRoles(fill: 0x7DBB47, onFill: 0x141414, tint: 0x243319, selectedTint: 0x334A20, accent: 0x69A929)
        ),
        PaletteColor(
            name: "Green", family: .chromatic, reference: 0x4EA558,
            light: PaletteRoles(fill: 0x75F484, onFill: 0x141414, tint: 0xDEF6DF, selectedTint: 0xC4EAC5, accent: 0x028C2C),
            dark: PaletteRoles(fill: 0x64CC6F, onFill: 0x141414, tint: 0x1D341F, selectedTint: 0x274C2A, accent: 0x279E3E)
        ),
        PaletteColor(
            name: "Grass", family: .chromatic, reference: 0x2CA86C,
            light: PaletteRoles(fill: 0x35F29A, onFill: 0x141414, tint: 0xDAF7E4, selectedTint: 0xBCEBCD, accent: 0x007948),
            dark: PaletteRoles(fill: 0x2AC37C, onFill: 0x141414, tint: 0x173524, selectedTint: 0x1B4E33, accent: 0x00AF6B)
        ),
        PaletteColor(
            name: "Emerald", family: .chromatic, reference: 0x00A87E,
            light: PaletteRoles(fill: 0x00FEC0, onFill: 0x141414, tint: 0xD6F8E9, selectedTint: 0xB6ECD5, accent: 0x008865),
            dark: PaletteRoles(fill: 0x00D09C, onFill: 0x141414, tint: 0x113529, selectedTint: 0x0D4E3A, accent: 0x009D75)
        ),
        PaletteColor(
            name: "Jade", family: .chromatic, reference: 0x00A78E,
            light: PaletteRoles(fill: 0x00F2CF, onFill: 0x141414, tint: 0xD3F8EE, selectedTint: 0xB1EDDD, accent: 0x007764),
            dark: PaletteRoles(fill: 0x00C1A5, onFill: 0x141414, tint: 0x0C362D, selectedTint: 0x004E42, accent: 0x00AD93)
        ),
        PaletteColor(
            name: "Mint", family: .chromatic, reference: 0x00A59B,
            light: PaletteRoles(fill: 0x00FFEF, onFill: 0x141414, tint: 0xD2F8F3, selectedTint: 0xAEECE5, accent: 0x00867D),
            dark: PaletteRoles(fill: 0x00CCBF, onFill: 0x141414, tint: 0x073532, selectedTint: 0x004E48, accent: 0x009B91)
        ),
        PaletteColor(
            name: "Teal", family: .chromatic, reference: 0x00A3A6,
            light: PaletteRoles(fill: 0x00F0F4, onFill: 0x141414, tint: 0xD1F7F8, selectedTint: 0xACECED, accent: 0x007577),
            dark: PaletteRoles(fill: 0x00BDC1, onFill: 0x141414, tint: 0x053536, selectedTint: 0x004D4E, accent: 0x00AAAD)
        ),
        PaletteColor(
            name: "Cyan", family: .chromatic, reference: 0x00A2B3,
            light: PaletteRoles(fill: 0x00E6FD, onFill: 0x141414, tint: 0xD1F7FD, selectedTint: 0xACEBF4, accent: 0x008493),
            dark: PaletteRoles(fill: 0x00C7DC, onFill: 0x141414, tint: 0x06343A, selectedTint: 0x004C54, accent: 0x0098A8)
        ),
        PaletteColor(
            name: "Sky", family: .chromatic, reference: 0x009FC2,
            light: PaletteRoles(fill: 0x00C6F1, onFill: 0x141414, tint: 0xD6F4FF, selectedTint: 0xAFE9FC, accent: 0x00738D),
            dark: PaletteRoles(fill: 0x00B8E0, onFill: 0x141414, tint: 0x0A333F, selectedTint: 0x004A5C, accent: 0x00A6CB)
        ),
        PaletteColor(
            name: "Azure", family: .chromatic, reference: 0x009BD6,
            light: PaletteRoles(fill: 0x00B8FF, onFill: 0x141414, tint: 0xDDF2FF, selectedTint: 0xBAE5FF, accent: 0x0080B2),
            dark: PaletteRoles(fill: 0x39BEFF, onFill: 0x141414, tint: 0x123142, selectedTint: 0x104863, accent: 0x0093CC)
        ),
        PaletteColor(
            name: "Blue", family: .chromatic, reference: 0x3D94E0,
            light: PaletteRoles(fill: 0x0077C6, onFill: 0xFFFFFF, tint: 0xE2F0FF, selectedTint: 0xC4E2FF, accent: 0x006EB6),
            dark: PaletteRoles(fill: 0x4EACFF, onFill: 0x141414, tint: 0x193045, selectedTint: 0x204567, accent: 0x269EFB)
        ),
        PaletteColor(
            name: "Cobalt", family: .chromatic, reference: 0x5D8EE4,
            light: PaletteRoles(fill: 0x2C6DE1, onFill: 0xFFFFFF, tint: 0xE6EFFF, selectedTint: 0xCCDFFF, accent: 0x3A73DB),
            dark: PaletteRoles(fill: 0x84B1FF, onFill: 0x141414, tint: 0x202E46, selectedTint: 0x2C4269, accent: 0x4C87F0)
        ),
        PaletteColor(
            name: "Indigo", family: .chromatic, reference: 0x7487E4,
            light: PaletteRoles(fill: 0x343AB5, onFill: 0xFFFFFF, tint: 0xE9EEFF, selectedTint: 0xD3DDFF, accent: 0x4D5DCB),
            dark: PaletteRoles(fill: 0x899EFF, onFill: 0x141414, tint: 0x262C46, selectedTint: 0x363F69, accent: 0x7B91FF)
        ),
        PaletteColor(
            name: "Iris", family: .chromatic, reference: 0x8781E0,
            light: PaletteRoles(fill: 0x5E48C8, onFill: 0xFFFFFF, tint: 0xECEDFF, selectedTint: 0xDADAFF, accent: 0x7366D9),
            dark: PaletteRoles(fill: 0xA9A5FF, onFill: 0x141414, tint: 0x2B2A45, selectedTint: 0x3F3C67, accent: 0x857AEF)
        ),
        PaletteColor(
            name: "Violet", family: .chromatic, reference: 0x997BD9,
            light: PaletteRoles(fill: 0x7240C0, onFill: 0xFFFFFF, tint: 0xF0EBFF, selectedTint: 0xE1D7FF, accent: 0x7950C1),
            dark: PaletteRoles(fill: 0xB28EFE, onFill: 0x141414, tint: 0x302843, selectedTint: 0x473A64, accent: 0xAA83F9)
        ),
        PaletteColor(
            name: "Purple", family: .chromatic, reference: 0xA875CF,
            light: PaletteRoles(fill: 0x9B51CD, onFill: 0xFFFFFF, tint: 0xF5E9FF, selectedTint: 0xEAD3FF, accent: 0x9A5AC8),
            dark: PaletteRoles(fill: 0xCF92FE, onFill: 0x141414, tint: 0x352740, selectedTint: 0x4E375F, accent: 0xAD6DDC)
        ),
        PaletteColor(
            name: "Orchid", family: .chromatic, reference: 0xB570C3,
            light: PaletteRoles(fill: 0xAB4ABD, onFill: 0xFFFFFF, tint: 0xFBE6FF, selectedTint: 0xF2D1F8, accent: 0x9945A9),
            dark: PaletteRoles(fill: 0xD381E3, onFill: 0x141414, tint: 0x39263C, selectedTint: 0x54355A, accent: 0xCE77DE)
        ),
        PaletteColor(
            name: "Plum", family: .chromatic, reference: 0xC16CB3,
            light: PaletteRoles(fill: 0xB843A9, onFill: 0xFFFFFF, tint: 0xFFE6FA, selectedTint: 0xF9CFF0, accent: 0xB750A9),
            dark: PaletteRoles(fill: 0xEC87DD, onFill: 0x141414, tint: 0x3C2438, selectedTint: 0x593353, accent: 0xCB63BC)
        ),
        PaletteColor(
            name: "Magenta", family: .chromatic, reference: 0xCA69A3,
            light: PaletteRoles(fill: 0xC33E93, onFill: 0xFFFFFF, tint: 0xFFE7F3, selectedTint: 0xFECEE8, accent: 0xB03C86),
            dark: PaletteRoles(fill: 0xEB78BD, onFill: 0x141414, tint: 0x3F2433, selectedTint: 0x5D324B, accent: 0xE76FB8)
        ),
        PaletteColor(
            name: "Pink", family: .chromatic, reference: 0xD06792,
            light: PaletteRoles(fill: 0xCB3A7E, onFill: 0xFFFFFF, tint: 0xFFE7EF, selectedTint: 0xFFCFDF, accent: 0xC94A82),
            dark: PaletteRoles(fill: 0xFF81B4, onFill: 0x141414, tint: 0x41232F, selectedTint: 0x603144, accent: 0xDE5D94)
        ),
        PaletteColor(
            name: "Graphite", family: .neutral, reference: 0x545559,
            light: PaletteRoles(fill: 0x545559, onFill: 0xFFFFFF, tint: 0xECEEF3, selectedTint: 0xDBDEE5, accent: 0x6E7585),
            dark: PaletteRoles(fill: 0xA3A4A8, onFill: 0x141414, tint: 0x2C2E32, selectedTint: 0x3F4248, accent: 0x818999)
        ),
        PaletteColor(
            name: "Slate", family: .neutral, reference: 0x536676,
            light: PaletteRoles(fill: 0x536676, onFill: 0xFFFFFF, tint: 0xE1F1FF, selectedTint: 0xC4E2FC, accent: 0x4B6A84),
            dark: PaletteRoles(fill: 0x99AABA, onFill: 0x141414, tint: 0x1E303F, selectedTint: 0x28455D, accent: 0x7C9CB8)
        ),
        PaletteColor(
            name: "Stone", family: .neutral, reference: 0x6D685F,
            light: PaletteRoles(fill: 0x6D685F, onFill: 0xFFFFFF, tint: 0xF3EEE3, selectedTint: 0xE5DDCD, accent: 0x7E735D),
            dark: PaletteRoles(fill: 0xB2ADA5, onFill: 0x141414, tint: 0x322D24, selectedTint: 0x494132, accent: 0x938871)
        ),
        PaletteColor(
            name: "Mauve", family: .neutral, reference: 0x736371,
            light: PaletteRoles(fill: 0x736371, onFill: 0xFFFFFF, tint: 0xFBE8F8, selectedTint: 0xF1D3ED, accent: 0x795E76),
            dark: PaletteRoles(fill: 0xB5A5B3, onFill: 0x141414, tint: 0x382736, selectedTint: 0x533850, accent: 0xAC8FA9)
        ),
        PaletteColor(
            name: "Sage", family: .neutral, reference: 0x637867,
            light: PaletteRoles(fill: 0x637867, onFill: 0xFFFFFF, tint: 0xE1F5E4, selectedTint: 0xC8E8CE, accent: 0x5C7D62),
            dark: PaletteRoles(fill: 0xA1B4A4, onFill: 0x141414, tint: 0x203324, selectedTint: 0x2C4B33, accent: 0x6F9175)
        ),
        PaletteColor(
            name: "Sand", family: .earth, reference: 0xCDBC9A,
            light: PaletteRoles(fill: 0xCDBC9A, onFill: 0x141414, tint: 0xF8EDD8, selectedTint: 0xEDDCBB, accent: 0x796435),
            dark: PaletteRoles(fill: 0xD1C3A5, onFill: 0x141414, tint: 0x362C18, selectedTint: 0x50401E, accent: 0xAC9566)
        ),
        PaletteColor(
            name: "Taupe", family: .neutral, reference: 0x846B62,
            light: PaletteRoles(fill: 0x846B62, onFill: 0xFFFFFF, tint: 0xFFE9E2, selectedTint: 0xFBD4C7, accent: 0x946C5E),
            dark: PaletteRoles(fill: 0xB69F97, onFill: 0x141414, tint: 0x3E2820, selectedTint: 0x5B382C, accent: 0xA88071)
        ),
        PaletteColor(
            name: "Brown", family: .earth, reference: 0x744B27,
            light: PaletteRoles(fill: 0x744B27, onFill: 0xFFFFFF, tint: 0xFEEADB, selectedTint: 0xF7D7BF, accent: 0x905B2A),
            dark: PaletteRoles(fill: 0xB0896B, onFill: 0x141414, tint: 0x3B2A1B, selectedTint: 0x583B24, accent: 0xC58C5C)
        ),
        PaletteColor(
            name: "Bronze", family: .earth, reference: 0x8D6850,
            light: PaletteRoles(fill: 0x8D6850, onFill: 0xFFFFFF, tint: 0xFFEADC, selectedTint: 0xF8D6C0, accent: 0x9C6A48),
            dark: PaletteRoles(fill: 0xB89781, onFill: 0x141414, tint: 0x3C291C, selectedTint: 0x593A26, accent: 0xB17E5B)
        ),
    ]

    /// `color` に最も近いパレットの色。同じ色への問い合わせは記憶した結果を返すので、描画のたびに呼んでよい。
    public static func color(for color: CalendarColor) -> PaletteColor {
        if let index = assignments.withLock({ $0[color] }) { return all[index] }
        let index = nearestIndex(to: color)
        assignments.withLock { $0[color] = index }
        return all[index]
    }

    /// 色のないカレンダーに使う、灰色の系統の Graphite。
    static let fallback: PaletteColor = all.first { $0.name == "Graphite" } ?? all[0]

    private static let assignments = Mutex<[CalendarColor: Int]>([:])

    // MARK: 割り当て

    /// 灰色の系統へ割り当てる彩度の上限（OKLab の a, b の距離）。これ未満は、色相に関わらず灰色の系統にする。
    static let neutralChromaLimit = 0.04
    /// 明度の差の重み。色相を保ったまま、暗い紺や薄い水色を同じ系統に寄せるため、a, b の差より小さくする。
    static let lightnessWeight = 0.25
    /// 灰色の系統の中で選ぶときの明度の差の重み。灰色の系統は明度の差が大きいので、色みの近さを優先する。
    static let neutralLightnessWeight = 0.05

    static func nearestIndex(to color: CalendarColor) -> Int {
        let target = OKLab(hex: UInt32(color.red) << 16 | UInt32(color.green) << 8 | UInt32(color.blue))
        let isNeutral = target.chroma < neutralChromaLimit
        var best = (index: 0, distance: Double.infinity)
        for (index, candidate) in all.enumerated() where (candidate.family == .neutral) == isNeutral {
            let distance = target.distance(to: references[index], lightnessWeight: isNeutral ? neutralLightnessWeight : lightnessWeight)
            if distance < best.distance { best = (index, distance) }
        }
        return best.index
    }

    private static let references: [OKLab] = all.map { OKLab(hex: $0.reference) }

    struct OKLab: Sendable {
        let lightness: Double
        let a: Double
        let b: Double

        var chroma: Double { (a * a + b * b).squareRoot() }

        init(hex: UInt32) {
            func linear(_ value: UInt32) -> Double {
                let c = Double(value) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let r = linear(hex >> 16 & 0xFF), g = linear(hex >> 8 & 0xFF), bl = linear(hex & 0xFF)
            let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
            let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
            let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
            lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        }

        func distance(to other: OKLab, lightnessWeight: Double) -> Double {
            let dl = (lightness - other.lightness) * lightnessWeight
            let da = a - other.a
            let db = b - other.b
            return (dl * dl + da * da + db * db).squareRoot()
        }
    }
}
