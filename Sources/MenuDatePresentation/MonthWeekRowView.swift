import MenuDateDomain
import SwiftUI
import Synchronization

/// 月表示の 1 週の行。マスの層と予定の層を重ね、クリックを行全体で 1 つのジェスチャーで受ける。
///
/// 予定ごとの `Text` や `Button` の View の階層を行ごとに作ると、スクロールで行が見え始めるフレームが間に合わないので、
/// 層ごとに 1 つの `Canvas` で描き、クリックは行全体で 1 つのジェスチャーにする。クリックの位置の判定は `MonthRowGeometry` が行い、描画と同じ寸法を使う。
///
/// 層は下から、日のボタン（描かない）、マス（日の数字、今日）、覆い（表示月の外の薄め、選択日の背景、マスの線）、予定（バー、時刻付きの予定、「他 N 件」）、選択日の枠である。
/// 層ごとに別の View にして、読む値を分ける。表示月が変わっても、日を選んでも、読む値が変わらない層の body は評価し直されない。
/// 特に、予定の層は選択日、表示月、今日を読まないので、見えている全行の予定の文字を描き直さない。
/// この View の body は ViewModel の値を読まない。位置から日や予定を求めるのは、タップされたときに ViewModel から読んで行う。
/// VoiceOver には各層の `accessibilityChildren` で、日、予定、「他 N 件」のボタンを見せる。
struct MonthWeekRowView: View {
    let viewModel: CalendarPopoverViewModel
    let weekIndex: Int
    let rowHeight: CGFloat

    /// 行の幅。クリックの位置から列を求めるのに使う。
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled

    /// VoiceOver かスイッチコントロールが動いているか。動いていなければ、日と予定のボタンを作らない（行を作るフレームの命令数が減る）。
    private var usesAssistiveTechnology: Bool { isVoiceOverEnabled || isSwitchControlEnabled }

    var body: some View {
        ZStack {
            if usesAssistiveTechnology { MonthWeekDayAccessibilityLayer(viewModel: viewModel, weekIndex: weekIndex) }
            MonthWeekCellsLayer(viewModel: viewModel, weekIndex: weekIndex)
            MonthWeekShadeLayer(viewModel: viewModel, weekIndex: weekIndex)
            MonthWeekEventsLayer(
                viewModel: viewModel, weekIndex: weekIndex, rowHeight: rowHeight, providesAccessibility: usesAssistiveTechnology
            )
            MonthWeekSelectionFrameLayer(viewModel: viewModel, weekIndex: weekIndex)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard width > 0 else { return }
            tap(at: location)
        }
        .accessibilityElement(children: .contain)
    }

    /// タップされた位置の日や予定を、そのときの ViewModel の値から求めて操作する。
    private func tap(at location: CGPoint) {
        let geometry = MonthRowGeometry(size: CGSize(width: width, height: rowHeight))
        let visible = viewModel.monthWeekLayout(at: weekIndex).visible(laneCapacity: geometry.laneCapacity)
        switch geometry.target(at: location, visible: visible) {
        case .day(let column):
            guard let day = viewModel.day(inWeek: weekIndex, column: column) else { return }
            viewModel.showSchedule(of: day)
        case .event(let id):
            // 押した予定の日を選んでから詳細を出す。詳細を閉じたとき、日の欄がその予定の日のスケジュールに戻る。
            if let day = viewModel.day(inWeek: weekIndex, column: geometry.column(at: location.x)) { viewModel.select(day) }
            viewModel.showDetail(of: id)
        case .more(let column):
            guard let day = viewModel.day(inWeek: weekIndex, column: column) else { return }
            viewModel.showSchedule(of: day)
        }
    }

    /// 「他 N 件」を出す列。
    static func hiddenColumns(_ visible: MonthWeekLayout.Visible) -> [Int] {
        visible.hiddenCountByColumn.indices.filter { visible.hiddenCountByColumn[$0] > 0 }
    }

    /// 時刻付きの予定は時刻とタイトル、バーはタイトルだけを読ませる。バーには終日の予定のほか、日をまたぐ時刻付きの予定も入る。
    static func accessibilityLabel(of item: MonthWeekLayout.Item) -> String {
        switch item.kind {
        case .timed(let timeText): "\(timeText) \(item.title)"
        case .bar: item.title
        }
    }
}

/// 選択日の枠の Canvas。選択日の列だけを入力にして描く。選択日が別の週に移っても、この週の列が変わらなければ描き直さない。
private struct MonthWeekSelectionFrameCanvas: View, Equatable {
    let column: Int

    var body: some View {
        let column = column
        Canvas { context, size in
            MonthWeekPainter.drawSelectionFrame(column: column, in: &context, geometry: MonthRowGeometry(size: size))
        }
    }
}

/// 日のボタンを VoiceOver に見せる。描かない。読む値は選択日で、表示月と今日は読まない。
private struct MonthWeekDayAccessibilityLayer: View {
    let viewModel: CalendarPopoverViewModel
    let weekIndex: Int

    var body: some View {
        let days = viewModel.dayAccessibility(inWeek: weekIndex)
        Color.clear
            .accessibilityChildren {
                HStack(spacing: 0) {
                    ForEach(days) { day in
                        Color.clear
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(day.label)
                            .accessibilityAddTraits(day.isSelected ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction(.default) {
                                if day.isSelectable { viewModel.showSchedule(of: day.day) }
                            }
                            .disabled(!day.isSelectable)
                    }
                }
            }
    }
}

/// マスの層。日の数字と今日の印だけを描く。読む値は今日だけで、表示月と選択日と予定は読まない。
///
/// 日の数字と今日の印は、表示月にも選択日にも依らないので、画像にして覚えておく（`MonthWeekImageStore`）。
/// 画像があれば貼るだけで、なければ描く。
private struct MonthWeekCellsLayer: View {
    let viewModel: CalendarPopoverViewModel
    let weekIndex: Int

    var body: some View {
        MonthWeekCellsCanvas(
            days: viewModel.monthWeekDays(at: weekIndex), weekIndex: weekIndex, store: viewModel.monthImageStore
        ).equatable()
    }
}

/// 7 日の表示内容だけを入力にして描く。この週の 7 日の表示内容が変わらなければ描き直さない。
private struct MonthWeekCellsCanvas: View, Equatable {
    let days: [MonthDayState]
    let weekIndex: Int
    let store: MonthWeekImageStore

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.days == rhs.days && lhs.weekIndex == rhs.weekIndex && lhs.store === rhs.store
    }

    var body: some View {
        let days = days
        let weekIndex = weekIndex
        let store = store
        Canvas { context, size in
            MonthWeekPainter.drawCells(days, week: weekIndex, store: store, in: &context, geometry: MonthRowGeometry(size: size))
        }
    }
}

/// 覆いの層。表示月の外のマスを薄め、選択日の背景を敷く。文字は描かない。日の数字の上、マスの線と予定の下に置く。
/// 読む値は表示月と選択日で、今日と予定は読まない。
///
/// 表示月が変わると、月の中に収まっていた行がすべて月の外になるので、見えている行のほとんどが変わる。
/// `Canvas` は描き直しだけでも 1 行あたり数百万命令かかるので、色を塗った View を置き、`Layout` で幅だけを変える。
private struct MonthWeekShadeLayer: View {
    let viewModel: CalendarPopoverViewModel
    let weekIndex: Int

    var body: some View {
        let outside = MonthWeekShade.Outside(columns: viewModel.outOfMonthColumns(inWeek: weekIndex))
        MonthWeekShadeLayout(outside: outside, selectedColumn: viewModel.selectedColumn(inWeek: weekIndex)) {
            MonthWeekShade.outOfMonthFill
            MonthWeekShade.outOfMonthFill
            MonthWeekShade.selectedFill
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 覆いの塗り。
enum MonthWeekShade {
    /// 表示月の外の列。週の中では、先頭から続く列と末尾まで続く列になる（週は連続した 7 日で、月も連続した日だから）。
    struct Outside: Equatable {
        let leading: Int
        let trailing: Int

        /// - Precondition: `columns` は先頭から続く列と末尾まで続く列だけからなる。
        init(columns: [Int]) {
            let count = MonthRowGeometry.columnCount
            var leading = 0
            while columns.contains(leading), leading < count { leading += 1 }
            // 全部が月の外なら、先頭から続く列として数える。
            var trailing = 0
            if leading < count {
                while columns.contains(count - 1 - trailing), trailing < count - leading { trailing += 1 }
            }
            self.leading = leading
            self.trailing = trailing
        }

        /// 列の集まりに戻す。
        var columns: [Int] {
            let count = MonthRowGeometry.columnCount
            return Array(0..<leading) + Array((count - trailing)..<count)
        }
    }

    /// 表示月の外のマスを、ポップオーバーの背景色の半透明の塗りで薄めて薄い灰色にする。
    static var outOfMonthFill: some View {
        Color(nsColor: .windowBackgroundColor).opacity(0.65).overlay(Color.primary.opacity(0.05))
    }

    static var selectedFill: some View { Color.accentColor.opacity(0.12) }
}

/// 覆いを置く。1 つ目が先頭から続く列、2 つ目が末尾まで続く列、3 つ目が選択日の列。幅が 0 のものは見えない。子の大きさは問い合わせない。
private struct MonthWeekShadeLayout: Layout {
    let outside: MonthWeekShade.Outside
    let selectedColumn: Int?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let cell = bounds.width / CGFloat(MonthRowGeometry.columnCount)
        func place(_ index: Int, column: Int, columns: Int) {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + CGFloat(column) * cell, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: CGFloat(columns) * cell, height: bounds.height)
            )
        }
        place(0, column: 0, columns: outside.leading)
        place(1, column: MonthRowGeometry.columnCount - outside.trailing, columns: outside.trailing)
        place(2, column: selectedColumn ?? 0, columns: selectedColumn == nil ? 0 : 1)
    }
}

/// 予定の層。バー、時刻付きの予定、「他 N 件」。読む値は予定、カレンダーの色、週の並びだけで、選択日、表示月、今日は読まない。
///
/// 入力（ViewModel、週の番号、行の高さ）が変わらなければ、SwiftUI は body を評価し直さず、予定の文字を描き直さない。
private struct MonthWeekEventsLayer: View {
    let viewModel: CalendarPopoverViewModel
    let weekIndex: Int
    let rowHeight: CGFloat
    /// VoiceOver などに予定のボタンを見せるか。
    let providesAccessibility: Bool

    var body: some View {
        let layout = viewModel.monthWeekLayout(at: weekIndex)
        let visible = layout.visible(laneCapacity: MonthRowGeometry.laneCapacity(rowHeight: rowHeight))
        let weekIndex = weekIndex
        let store = viewModel.monthImageStore
        Canvas { context, size in
            let geometry = MonthRowGeometry(size: size)
            MonthWeekPainter.drawGridLines(in: &context, geometry: geometry)
            MonthWeekPainter.drawEvents(visible, week: weekIndex, store: store, in: &context, geometry: geometry)
        }
        .modifier(EventAccessibility(isEnabled: providesAccessibility, viewModel: viewModel, weekIndex: weekIndex, visible: visible))
    }
}

/// 予定と「他 N 件」のボタンを VoiceOver に見せる。`isEnabled` が `false` なら何も付けない。
private struct EventAccessibility: ViewModifier {
    let isEnabled: Bool
    let viewModel: CalendarPopoverViewModel
    let weekIndex: Int
    let visible: MonthWeekLayout.Visible

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityChildren { buttons }
        } else {
            content
        }
    }

    private var buttons: some View {
        VStack(spacing: 0) {
            ForEach(visible.items) { item in
                Color.clear
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(MonthWeekRowView.accessibilityLabel(of: item))
                    .accessibilityHint("予定の詳細を開く")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default) { viewModel.showDetail(of: item.id) }
            }
            ForEach(MonthWeekRowView.hiddenColumns(visible), id: \.self) { column in
                Color.clear
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(viewModel.dayHeader(inWeek: weekIndex, column: column))、他 \(visible.hiddenCountByColumn[column]) 件")
                    .accessibilityHint("この日のスケジュールを表示する")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default) {
                        if let day = viewModel.day(inWeek: weekIndex, column: column) { viewModel.showSchedule(of: day) }
                    }
            }
        }
    }
}

/// 選択日の枠。バーや予定の上に重ねるので、予定の層より上に置く。読む値は選択日だけ。
private struct MonthWeekSelectionFrameLayer: View {
    let viewModel: CalendarPopoverViewModel
    let weekIndex: Int

    var body: some View {
        // 選択日がない週は、描くものがないので Canvas を作らない。
        if let column = viewModel.selectedColumn(inWeek: weekIndex) {
            MonthWeekSelectionFrameCanvas(column: column).equatable()
        }
    }
}

/// 1 週の行を `GraphicsContext` に描く。
///
/// 文字は `Text(verbatim:)` で作り、ローカライズの辞書を引かない。マスの幅に収まらない文字は、末尾を「…」で省略する。
enum MonthWeekPainter {
    fileprivate static let numberFont = Font.system(size: 12)
    fileprivate static let titleFont = Font.system(size: 11)
    fileprivate static let timeFont = Font.system(size: 10).monospacedDigit()
    fileprivate static let moreFont = Font.system(size: 10)
    private static let barHeight = MonthRowGeometry.laneHeight - 2
    private static let barRadius: CGFloat = 4
    private static let dotSize: CGFloat = 6
    private static let numberBadgeHeight: CGFloat = 20
    private static let gridLine = Color.primary.opacity(0.12)

    /// 選択日の枠。線と予定の上に重ねる。
    static func drawSelectionFrame(column: Int, in context: inout GraphicsContext, geometry: MonthRowGeometry) {
        let frame = geometry.cellRect(column: column).insetBy(dx: 0.75, dy: 0.75)
        context.stroke(Path(frame), with: .color(.accentColor), lineWidth: 1.5)
    }

    /// 日の数字と今日。画像があれば貼り、なければ描く。
    static func drawCells(_ days: [MonthDayState], week: Int, store: MonthWeekImageStore, in context: inout GraphicsContext, geometry: MonthRowGeometry) {
        switch store.cells(week: week, days: days, spec: imageSpec(in: context, geometry: geometry)) {
        case .image(let image, let rect): drawImage(image, in: rect, context: &context)
        case .empty: break
        case .miss: drawCells(days, in: &context, geometry: geometry)
        }
    }

    /// バー、時刻付きの予定、「他 N 件」。画像があれば貼り、なければ描く。
    static func drawEvents(_ visible: MonthWeekLayout.Visible, week: Int, store: MonthWeekImageStore, in context: inout GraphicsContext, geometry: MonthRowGeometry) {
        switch store.events(week: week, visible: visible, spec: imageSpec(in: context, geometry: geometry)) {
        case .image(let image, let rect): drawImage(image, in: rect, context: &context)
        case .empty: break
        case .miss: drawEvents(visible, in: &context, geometry: geometry)
        }
    }

    static func imageSpec(in context: GraphicsContext, geometry: MonthRowGeometry) -> MonthWeekImageStore.Spec {
        MonthWeekImageStore.Spec(size: geometry.size, colorScheme: context.environment.colorScheme, displayScale: context.environment.displayScale)
    }

    /// 画像の 1 画素が、画面の 1 画素に当たるように貼る。
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: inout GraphicsContext) {
        let scale = CGFloat(image.width) / rect.width
        context.draw(Image(decorative: image, scale: scale), in: rect)
    }

    /// 日の数字と今日。
    static func drawCells(_ days: [MonthDayState], in context: inout GraphicsContext, geometry: MonthRowGeometry) {
        for (column, day) in days.enumerated() {
            drawCell(day, column: column, in: &context, geometry: geometry)
        }
    }

    /// バー、時刻付きの予定、「他 N 件」。
    static func drawEvents(_ visible: MonthWeekLayout.Visible, in context: inout GraphicsContext, geometry: MonthRowGeometry) {
        for item in visible.items {
            draw(item, in: &context, geometry: geometry)
        }
        for (column, count) in visible.hiddenCountByColumn.enumerated() where count > 0 {
            drawMore(count, column: column, in: &context, geometry: geometry)
        }
    }

    private static func drawCell(_ cell: MonthDayState, column: Int, in context: inout GraphicsContext, geometry: MonthRowGeometry) {
        let rect = geometry.cellRect(column: column)
        // 月の 1 日は「11月1日」のように月を付ける。
        let label = cell.day.day == 1 ? "\(cell.day.month)月1日" : String(cell.number)
        let resolved = resolvedText(label, style: .number, color: numberColor(cell), in: context)
        let textWidth = numberWidth(label, resolved: resolved)
        let badge = CGRect(
            x: rect.minX + 4, y: 2,
            width: max(numberBadgeHeight, textWidth + 10), height: numberBadgeHeight
        )
        if cell.isToday {
            // 今日は塗りつぶした形（数字だけなら円、月を付けるときは両端が円の帯）にして、色だけで区別しない。
            context.fill(Path(roundedRect: badge, cornerRadius: numberBadgeHeight / 2), with: .color(.accentColor))
        }
        context.draw(resolved, at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)
    }

    /// 日の数字の幅。同じ文字列は一度だけ測る。
    private static let numberWidths = Mutex<[String: CGFloat]>([:])

    private static func numberWidth(_ label: String, resolved: GraphicsContext.ResolvedText) -> CGFloat {
        if let width = numberWidths.withLock({ $0[label] }) { return width }
        let width = resolved.measure(in: CGSize(width: 200, height: 40)).width
        numberWidths.withLock { $0[label] = width }
        return width
    }

    private static func numberColor(_ cell: MonthDayState) -> TextColor {
        if cell.isToday { return .white }
        return switch cell.weekdayKind {
        case .sunday: .red
        case .saturday: .blue
        case .weekday: .primary
        }
    }

    /// 文字の色。解決した文字の記憶のキーにするため、`Color` でなくこの列挙で持つ。
    private enum TextColor: Hashable {
        case white, primary, secondary, red, blue

        var value: Color {
            switch self {
            case .white: Color.white
            case .primary: Color.primary
            case .secondary: Color.secondary
            case .red: Color.red
            case .blue: Color.blue
            }
        }
    }

    /// 解決した文字は `Sendable` でないが、作ったあとは変えないので、`Mutex` の中に入れてよい。
    private struct ResolvedBox: @unchecked Sendable {
        let value: GraphicsContext.ResolvedText
    }

    private struct ResolvedKey: Hashable {
        let style: TextStyle
        let text: String
        let color: TextColor
        let colorScheme: ColorScheme
        let displayScale: Int
    }

    /// 解決した文字の記憶。文字の解決は、フォントの検索と字形の準備を含むので重く、同じ日の数字や時刻やタイトルが何度も出る。
    /// 色は環境（ライトとダーク）で変わるので、`colorScheme` と `displayScale` をキーに含める。
    private static let resolvedCache = Mutex<[ResolvedKey: ResolvedBox]>([:])

    private static func resolvedText(_ text: String, style: TextStyle, color: TextColor, in context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let key = ResolvedKey(
            style: style, text: text, color: color,
            colorScheme: context.environment.colorScheme, displayScale: Int(context.environment.displayScale * 100)
        )
        if let box = resolvedCache.withLock({ $0[key] }) { return box.value }
        var view = Text(verbatim: text).font(style.font)
        if style == .number { view = view.monospacedDigit() }
        let resolved = context.resolve(view.foregroundColor(color.value))
        resolvedCache.withLock { cache in
            if cache.count >= fitCacheLimit { cache.removeAll() }
            cache[key] = ResolvedBox(value: resolved)
        }
        return resolved
    }

    /// マスの線。各マスの右辺と下辺、左端の列の左辺に線を引く。隣の行と線が重ならないようにする。
    /// 表示月の外の薄めの上、予定の下に重ねるので、薄めの影響を受けない。
    static func drawGridLines(in context: inout GraphicsContext, geometry: MonthRowGeometry) {
        var path = Path()
        for column in 0..<MonthRowGeometry.columnCount {
            let x = geometry.cellRect(column: column).maxX
            path.move(to: CGPoint(x: x - 0.5, y: 0))
            path.addLine(to: CGPoint(x: x - 0.5, y: geometry.size.height))
        }
        path.move(to: CGPoint(x: 0.5, y: 0))
        path.addLine(to: CGPoint(x: 0.5, y: geometry.size.height))
        path.move(to: CGPoint(x: 0, y: geometry.size.height - 0.5))
        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - 0.5))
        context.stroke(path, with: .color(gridLine), lineWidth: 1)
    }

    /// 予定の画像に切り出す範囲（行の座標）。予定のある行の範囲で、幅は行の全体である。描くものがなければ `nil`。
    static func eventsExtent(_ visible: MonthWeekLayout.Visible, geometry: MonthRowGeometry) -> CGRect? {
        var lastLane = visible.items.map(\.lane).max() ?? -1
        if visible.hiddenCountByColumn.contains(where: { $0 > 0 }) { lastLane = max(lastLane, geometry.laneCapacity - 1) }
        guard lastLane >= 0 else { return nil }
        let top = MonthRowGeometry.dayHeaderHeight
        let bottom = min(geometry.size.height, top + CGFloat(lastLane + 1) * MonthRowGeometry.laneHeight)
        return CGRect(x: 0, y: top, width: geometry.size.width, height: bottom - top)
    }

    private static func draw(_ item: MonthWeekLayout.Item, in context: inout GraphicsContext, geometry: MonthRowGeometry) {
        var context = context
        if item.isPast { context.opacity = 0.45 }
        let color = item.color?.swiftUIColor ?? Color.gray
        let lane = geometry.laneRect(lane: item.lane, columns: item.columns)
        let row = CGRect(x: lane.minX, y: lane.minY + 1, width: lane.width, height: barHeight)
        switch item.kind {
        case .bar(let continuesFromPrevious, let continuesToNext):
            // 前後の週へ続く側は、マスの端まで伸ばして角を付けない。
            let left = continuesFromPrevious ? row.minX - MonthRowGeometry.horizontalInset : row.minX
            let right = continuesToNext ? row.maxX + MonthRowGeometry.horizontalInset : row.maxX
            let bar = CGRect(x: left, y: row.minY, width: right - left, height: row.height)
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: continuesFromPrevious ? 0 : barRadius,
                bottomLeadingRadius: continuesFromPrevious ? 0 : barRadius,
                bottomTrailingRadius: continuesToNext ? 0 : barRadius,
                topTrailingRadius: continuesToNext ? 0 : barRadius
            )
            context.fill(shape.path(in: bar), with: .color(color))
            drawText(
                item.title, style: .title, color: .white, in: &context,
                from: bar.minX + 6, to: bar.maxX - 4, midY: bar.midY
            )
        case .timed(let timeText):
            let dot = CGRect(x: row.minX + 4, y: row.midY - dotSize / 2, width: dotSize, height: dotSize)
            context.fill(Path(ellipseIn: dot), with: .color(color))
            let timeX = dot.maxX + 4
            let timeWidth = drawText(
                timeText, style: .time, color: .secondary, in: &context,
                from: timeX, to: row.maxX - 2, midY: row.midY
            )
            drawText(
                item.title, style: .title, color: .primary, in: &context,
                from: timeX + timeWidth + 4, to: row.maxX - 2, midY: row.midY
            )
        }
    }

    private static func drawMore(_ count: Int, column: Int, in context: inout GraphicsContext, geometry: MonthRowGeometry) {
        let lane = geometry.laneRect(lane: geometry.laneCapacity - 1, columns: column..<(column + 1))
        drawText(
            "他 \(count) 件", style: .more, color: .secondary, in: &context,
            from: lane.minX + 6, to: lane.maxX - 2, midY: lane.midY
        )
    }

    /// 文字の種類。幅の測定結果を覚えるときの区別にも使う。
    private enum TextStyle: Hashable {
        case title, time, more, number

        var font: Font {
            switch self {
            case .number: MonthWeekPainter.numberFont
            case .title: MonthWeekPainter.titleFont
            case .time: MonthWeekPainter.timeFont
            case .more: MonthWeekPainter.moreFont
            }
        }
    }

    /// 文字を幅に収めた結果。`text` が `nil` なら、1 文字も収まらない。
    private struct Fit: Sendable {
        let text: String?
        let width: CGFloat
    }

    private struct FitKey: Hashable {
        let style: TextStyle
        let text: String
        /// 収める幅を 0.5pt 単位に丸めた値。
        let available: Int
    }

    /// 収めた結果の記憶。文字の測定は重く、同じタイトルや時刻が何度も出るため、測定結果を覚えておく。
    /// 行はスクロールで見え始めるたびに描かれ、そのフレームの CPU 時間に響く。大きくなりすぎないよう、上限を超えたら捨てる。
    private static let fitCache = Mutex<[FitKey: Fit]>([:])
    private static let fitCacheLimit = 20_000

    /// 1 行の文字を、`from` から `to` の幅に収めて描く。収まらないときは末尾を「…」にする。描いた文字の幅を返す。
    @discardableResult
    private static func drawText(
        _ string: String, style: TextStyle, color: TextColor, in context: inout GraphicsContext,
        from minX: CGFloat, to maxX: CGFloat, midY: CGFloat
    ) -> CGFloat {
        let available = maxX - minX
        guard available > 0 else { return 0 }
        let key = FitKey(style: style, text: string, available: Int((available * 2).rounded(.down)))
        let fit = fitCache.withLock { $0[key] } ?? makeFit(string, style: style, available: available, in: context, key: key)
        guard let text = fit.text else { return 0 }
        let resolved = resolvedText(text, style: style, color: color, in: context)
        context.draw(resolved, at: CGPoint(x: minX, y: midY), anchor: .leading)
        return fit.width
    }

    /// 文字を測り、幅に収まる文字数を求めて記憶する。
    private static func makeFit(_ string: String, style: TextStyle, available: CGFloat, in context: GraphicsContext, key: FitKey) -> Fit {
        func measure(_ text: String) -> CGFloat {
            context.resolve(Text(verbatim: text).font(style.font)).measure(in: CGSize(width: 10_000, height: 100)).width
        }
        var fit = Fit(text: string, width: measure(string))
        if fit.width > available {
            // 全体の幅との比で文字数を見積もり、収まるまで 1 文字ずつ減らす。
            let characters = Array(string)
            var count = min(characters.count - 1, Int(Double(characters.count) * available / fit.width))
            fit = Fit(text: nil, width: 0)
            while count > 0 {
                let candidate = String(characters[..<count]) + "…"
                let width = measure(candidate)
                if width <= available {
                    fit = Fit(text: candidate, width: width)
                    break
                }
                count -= 1
            }
        }
        fitCache.withLock { cache in
            if cache.count >= fitCacheLimit { cache.removeAll() }
            cache[key] = fit
        }
        return fit
    }
}
