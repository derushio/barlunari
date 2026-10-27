import BarlunariDomain
import SwiftUI

extension Color {
    /// `0xRRGGBB` の sRGB の色。
    init(hex: UInt32) {
        self.init(
            red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255
        )
    }
}

extension PaletteRoles {
    var fillColor: Color { Color(hex: fill) }
    var onFillColor: Color { Color(hex: onFill) }
    var tintColor: Color { Color(hex: tint) }
    var selectedTintColor: Color { Color(hex: selectedTint) }
    var accentColor: Color { Color(hex: accent) }
}

extension CalendarColor {
    /// このカレンダーの色に割り当てたパレットの色の、`colorScheme` での役割別の色。
    func paletteRoles(_ colorScheme: ColorScheme) -> PaletteRoles {
        CalendarPalette.color(for: self).roles(isDark: colorScheme == .dark)
    }
}

extension Optional where Wrapped == CalendarColor {
    /// 色のないカレンダーは、灰色の系統の Graphite で描く。
    func paletteRoles(_ colorScheme: ColorScheme) -> PaletteRoles {
        switch self {
        case .some(let color): color.paletteRoles(colorScheme)
        case .none: CalendarPalette.fallback.roles(isDark: colorScheme == .dark)
        }
    }
}
