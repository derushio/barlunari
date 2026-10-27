import BarlunariDomain
import SwiftUI

/// コンパクト表示の、曜日の行と、週の行が連続して流れる月のマス目。
///
/// 曜日の行はスクロールの外に固定する。週の行のスクロールは `WeekScrollView` が行う。
struct MonthGridView: View {
    /// 週の行の高さ。日のマスの高さに、行の間の余白 2pt を足した値。
    static let rowHeight: CGFloat = 33
    /// 最後の行の下の余白を含めない、6 週分の高さ。
    static let visibleHeight: CGFloat = rowHeight * CGFloat(WeekTimeline.visibleWeekCount) - 2

    let viewModel: CalendarPopoverViewModel

    var body: some View {
        VStack(spacing: 2) {
            WeekdayHeaderRow(viewModel: viewModel)
            WeekScrollView(viewModel: viewModel, rowHeight: Self.rowHeight, viewportHeight: Self.visibleHeight) { index in
                WeekRowView(viewModel: viewModel, weekIndex: index)
            }
        }
    }
}

/// 曜日の行。月曜始まりなど、週の開始曜日に従う。
struct WeekdayHeaderRow: View {
    let viewModel: CalendarPopoverViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(viewModel.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 1 週の行。自分の週の日だけを ViewModel から読み、1 つの `Canvas` で描く。
///
/// 7 マス分の View の階層（`VStack`、`ZStack`、`Circle`、`Text`、ジェスチャー、アクセシビリティの修飾子）を行ごとに作ると、
/// スクロールで行が見え始めるフレームが間に合わないので、描画は 1 つの `Canvas`、クリックは行全体で 1 つのジェスチャーにする。
/// VoiceOver には `accessibilityChildren` でマスごとのボタンを見せる。
private struct WeekRowView: View {
    let viewModel: CalendarPopoverViewModel
    let weekIndex: Int

    /// 行の幅。クリックの位置から列を求めるのに使う。
    @State private var width: CGFloat = 0

    private static let cellCount = 7
    private static let circleSize: CGFloat = 24
    private static let dotSize: CGFloat = 4
    private static let dotSpacing: CGFloat = 2

    var body: some View {
        let cells = viewModel.weekCells(at: weekIndex)
        Canvas { context, size in
            Self.draw(cells, in: &context, size: size)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard width > 0 else { return }
            let column = Int(location.x / (width / CGFloat(Self.cellCount)))
            guard cells.indices.contains(column), cells[column].isSelectable else { return }
            viewModel.select(cells[column].day)
        }
        .accessibilityChildren {
            HStack(spacing: 0) {
                ForEach(cells) { cell in
                    Color.clear
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(cell.accessibilityLabel)
                        .accessibilityAddTraits(cell.isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction(.default) {
                            if cell.isSelectable { viewModel.select(cell.day) }
                        }
                        .disabled(!cell.isSelectable)
                }
            }
        }
    }

    private static func draw(_ cells: [DayCellState], in context: inout GraphicsContext, size: CGSize) {
        let cellWidth = size.width / CGFloat(cellCount)
        for (column, state) in cells.enumerated() {
            let centerX = (CGFloat(column) + 0.5) * cellWidth
            // マスの上下の余白は 1pt。円の領域は上端から 1pt 下に置く。
            let circleRect = CGRect(x: centerX - circleSize / 2, y: 1, width: circleSize, height: circleSize)
            if state.isToday {
                context.fill(Path(ellipseIn: circleRect), with: .color(.accentColor))
            }
            if state.isSelected {
                // strokeBorder と同じく、枠が円の領域の内側に収まるようにする。
                let stroke = circleRect.insetBy(dx: 0.75, dy: 0.75)
                let color: Color = state.isToday ? Color.primary.opacity(0.7) : .accentColor
                context.stroke(Path(ellipseIn: stroke), with: .color(color), lineWidth: 1.5)
            }
            // 数字は翻訳しないので、ローカライズの辞書を引かない verbatim にする。行を描くたびに 7 回引くと、行が見え始めるフレームが重くなる。
            let text = Text(verbatim: String(state.number))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundColor(numberColor(state))
            context.draw(context.resolve(text), at: CGPoint(x: circleRect.midX, y: circleRect.midY), anchor: .center)

            let dots = state.dotColors
            guard !dots.isEmpty else { continue }
            let dotsWidth = CGFloat(dots.count) * dotSize + CGFloat(dots.count - 1) * dotSpacing
            let dotsTop = circleRect.maxY + 1
            var dotContext = context
            dotContext.opacity = state.isInMonth ? 1 : 0.4
            for (index, color) in dots.enumerated() {
                let x = centerX - dotsWidth / 2 + CGFloat(index) * (dotSize + dotSpacing)
                dotContext.fill(Path(ellipseIn: CGRect(x: x, y: dotsTop, width: dotSize, height: dotSize)), with: .color(color.paletteRoles(context.environment.colorScheme).accentColor))
            }
        }
    }

    private static func numberColor(_ state: DayCellState) -> Color {
        if state.isToday { return .white }
        let base: Color = switch state.weekdayKind {
        case .sunday: .red
        case .saturday: .blue
        case .weekday: .primary
        }
        return state.isInMonth ? base : base.opacity(0.35)
    }
}
