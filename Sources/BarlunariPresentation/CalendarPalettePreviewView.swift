import SwiftUI

/// パレットの全色を、役割ごとに並べた一覧。色の見やすさの確認に使う。外観は環境の `colorScheme` に従う。
/// 各色に、名前、塗りに文字を載せた帯、薄い背景のブロックに標準の文字、点と線を並べる。
public struct CalendarPalettePreviewView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let columnCount: Int

    public init(columnCount: Int = 5) {
        self.columnCount = columnCount
    }

    public var body: some View {
        let colors = CalendarPalette.all
        let rows = stride(from: 0, to: colors.count, by: columnCount).map { Array(colors[$0..<min($0 + columnCount, colors.count)]) }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rows[rowIndex], id: \.name) { color in
                        PaletteSwatchCard(color: color.roles(isDark: colorScheme == .dark), name: color.name)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(width: CGFloat(columnCount) * 210 + 32, alignment: .leading)
    }
}

private struct PaletteSwatchCard: View {
    let color: PaletteRoles
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption.weight(.semibold))
            // 塗りと、塗りの上の文字（月表示の終日の帯）。
            Text("終日の予定")
                .font(.caption)
                .foregroundStyle(color.onFillColor)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(color.fillColor))
            // 薄い背景と標準の文字、左端の線（日の欄のブロック）。選択中は濃い背景と枠線。
            HStack(spacing: 4) {
                block(background: color.tintColor, border: nil)
                block(background: color.selectedTintColor, border: color.accentColor)
            }
            // 点と線（一覧の線、月表示の点）。
            HStack(spacing: 6) {
                Circle().fill(color.accentColor).frame(width: 8, height: 8)
                Circle().fill(color.accentColor).frame(width: 8, height: 8)
                RoundedRectangle(cornerRadius: 1.5).fill(color.accentColor).frame(height: 3)
            }
        }
        .frame(width: 200)
    }

    private func block(background: Color, border: Color?) -> some View {
        Text("会議 10:00")
            .font(.caption)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4).fill(background))
            .overlay { if let border { RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: 2) } }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5).fill(color.accentColor).frame(width: 3).padding(.vertical, 1)
            }
    }
}
