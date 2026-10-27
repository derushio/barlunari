import BarlunariDomain
import SwiftUI

/// 月表示の日の欄。選択日の 1 日のスケジュールを出す。2 列のときは、予定の詳細と表示するカレンダーの一覧も、スケジュールと入れ替えて出す。
/// 読む値は、2 列のときの `eventDetail` と `isCalendarFilterOpen` だけ（3 列では何も読まない）。
///
/// 3 列（`showsDetail == false`）では、詳細と一覧は詳細の列（`MonthDetailColumn`）に出すので、日の欄は常にスケジュールだけを出す。
/// 2 列では、詳細と一覧を出している間もスケジュールを階層に残し、見えなくして操作とアクセシビリティから外す。
/// 詳細から戻ったときに、利用者が動かした時間軸のスクロール位置を保つため。入れ替えにアニメーションは付けない。
/// リンクと「参加」ボタンは、コンパクト表示と同じく ViewModel 経由で開く。
struct MonthDayPane: View {
    let viewModel: CalendarPopoverViewModel
    /// 詳細と一覧を、この欄でスケジュールと入れ替えて出すか。2 列のとき true。
    let showsDetail: Bool
    /// 詳細の内容の高さの上限。
    let contentMaxHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if showsDetail {
                coveredContent
            } else {
                DayScheduleView(viewModel: viewModel)
            }
        }
        .padding(.leading, MonthPopoverSizing.dayPaneLeadingInset)
        .padding(.trailing, MonthPopoverSizing.dayPaneTrailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .openingURLsThrough(viewModel)
    }

    @ViewBuilder
    private var coveredContent: some View {
        let detail = viewModel.eventDetail
        let isFilterOpen = viewModel.isCalendarFilterOpen
        let isCovered = detail != nil || isFilterOpen
        DayScheduleView(viewModel: viewModel)
            .opacity(isCovered ? 0 : 1)
            .allowsHitTesting(!isCovered)
            .accessibilityHidden(isCovered)
        if let detail {
            EventDetailView(
                detail: detail, onBack: viewModel.closeDetail, contentMaxHeight: contentMaxHeight,
                backTitle: "スケジュール", backAccessibilityLabel: "スケジュールに戻る"
            )
            .frame(maxHeight: .infinity, alignment: .top)
        } else if isFilterOpen {
            CalendarFilterView(viewModel: viewModel)
        }
    }
}

/// 月表示の予定の詳細の列（3 列のとき）。予定の詳細、表示するカレンダーの一覧、予定を選んでいないときの空の状態のうち 1 つを出す。
/// 読む値は `eventDetail` と `isCalendarFilterOpen`。
///
/// 列は常に置く。日の欄のスケジュールは、詳細や一覧を出している間も動かさない。
/// 詳細は閉じるボタンと Esc で閉じて、空の状態に戻る。
struct MonthDetailColumn: View {
    let viewModel: CalendarPopoverViewModel
    /// 詳細の内容の高さの上限。
    let contentMaxHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if let detail = viewModel.eventDetail {
                EventDetailView(
                    detail: detail, onBack: viewModel.closeDetail, contentMaxHeight: contentMaxHeight,
                    backTitle: "", backAccessibilityLabel: "詳細を閉じる", showsCloseButton: true
                )
                .frame(maxHeight: .infinity, alignment: .top)
            } else if viewModel.isCalendarFilterOpen {
                CalendarFilterView(viewModel: viewModel)
            } else {
                ContentUnavailableView {
                    Label("予定が選択されていません", systemImage: "calendar")
                } description: {
                    Text("スケジュールかカレンダーの予定をクリックすると、ここに詳細を表示します")
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.leading, MonthPopoverSizing.detailColumnLeadingInset)
        .padding(.trailing, MonthPopoverSizing.detailColumnTrailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .openingURLsThrough(viewModel)
    }
}

extension View {
    /// リンクと「参加」ボタンを、ViewModel 経由で開く。
    fileprivate func openingURLsThrough(_ viewModel: CalendarPopoverViewModel) -> some View {
        environment(\.openURL, OpenURLAction { url in
            viewModel.open(url)
            return .handled
        })
    }
}

/// 時間軸の寸法。
enum DayTimelineMetrics {
    /// 1 時間あたりの高さ。
    static let hourHeight: CGFloat = 48
    /// 時刻の目盛りの幅。
    static let labelWidth: CGFloat = 40
    /// 目盛りとブロックの間隔。
    static let labelGap: CGFloat = 6
    /// 時間軸の上下の余白。0:00 の目盛りが切れないようにする。
    static let verticalInset: CGFloat = 8
    /// ブロックの間隔。
    static let blockGap: CGFloat = 1
    /// ブロックを置く領域の幅。
    static let eventAreaWidth: CGFloat =
        MonthPopoverSizing.dayPaneWidth - MonthPopoverSizing.dayPaneLeadingInset - MonthPopoverSizing.dayPaneTrailingInset
        - labelWidth - labelGap - 12
    /// 1 分あたりの高さ。
    static var pointsPerMinute: CGFloat { hourHeight / 60 }
    /// 時間軸全体の高さ。
    static var totalHeight: CGFloat { hourHeight * 24 }
    /// スクロール位置を揃える単位の数（30 分ごと）。
    static var slotCount: Int { 24 * 60 / DayScheduleScroll.slotMinutes }
    static var slotHeight: CGFloat { CGFloat(DayScheduleScroll.slotMinutes) * pointsPerMinute }
    /// スクロール位置を合わせた罫線と、時間軸の枠の上端との間隔。上の余白と同じにし、0:00 と同じ見え方にする。
    static var topClearance: CGFloat { verticalInset }
    /// 余白を含む、スクロールする内容の高さ。
    static var contentHeight: CGFloat { totalHeight + verticalInset * 2 }

    /// `minute` を一番上にするときに使う、30 分ごとの位置の番号。
    ///
    /// 目標の位置まで内容が足りず、スクロールが末尾で止まると、一番上が罫線からずれて目盛りの文字が切れる。
    /// そうならないよう、末尾で止まらずに届く 30 分ごとの位置のうち、目標以下で一番遅いものにする。
    static func reachableSlot(for minute: Int, viewportHeight: CGFloat) -> Int {
        let target = max(0, minute) / DayScheduleScroll.slotMinutes
        let reachable = Int(((contentHeight - viewportHeight) / slotHeight).rounded(.down))
        return max(0, min(target, reachable, slotCount - 1))
    }
}

/// 日の欄のスケジュール。1 分ごとに作り直し、現在時刻の線と過去の予定の薄めを更新する。
struct DayScheduleView: View {
    let viewModel: CalendarPopoverViewModel

    var body: some View {
        TimelineView(.everyMinute) { context in
            DayScheduleContent(viewModel: viewModel, tick: context.date)
        }
    }
}

/// スクロールの位置を決め直す契機。選択日が変わったとき、選択日の予定を読み込み終えたとき、時間軸の枠の高さが変わったとき。
private struct DayScrollKey: Equatable {
    let day: CalendarDay
    let isLoaded: Bool
    let viewportHeight: CGFloat
}

private struct DayScheduleContent: View {
    let viewModel: CalendarPopoverViewModel
    /// 1 分ごとに変わる値。変わると、この View の body が評価し直される。
    let tick: Date
    /// 時間軸の枠の高さ。終日の予定の有無とパネルの高さで変わる。
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)

    var body: some View {
        let schedule = viewModel.selectedDaySchedule
        let selectedID = viewModel.detailEventID
        VStack(alignment: .leading, spacing: 8) {
            header(schedule)
            if schedule.isUnavailable {
                message("予定を表示できません")
            } else if !schedule.isLoaded {
                message("読み込み中…")
            } else {
                if !schedule.allDay.isEmpty { allDaySection(schedule.allDay, selectedID: selectedID) }
                if schedule.isEmpty {
                    Text("予定はありません").font(.callout).foregroundStyle(.secondary)
                }
                timeline(schedule, selectedID: selectedID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ schedule: DayScheduleState) -> some View {
        HStack(spacing: 6) {
            Text(schedule.title).font(.title3.weight(.semibold))
            if let label = schedule.relativeLabel {
                Text(label).font(.callout.weight(.medium)).foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .frame(height: MonthPopoverSizing.headerHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 終日の予定

    private func allDaySection(_ items: [DayScheduleItem], selectedID: CalendarEvent.Identity?) -> some View {
        ScrollView {
            VStack(spacing: 3) {
                ForEach(items) { item in
                    AllDayItemRow(item: item, isSelected: item.id == selectedID) { viewModel.showDetail(of: item.id) }
                }
            }
        }
        .frame(height: min(CGFloat(items.count) * 25, 100))
    }

    // MARK: 時間軸

    /// 時間軸。罫線、目盛り、予定のブロック、現在時刻の線を `DayTimelineCanvas` の 1 つの `Canvas` で描く。
    /// 日の欄の View の数が多いと、隣のマス目をスクロールしている間の 1 フレームの処理が増えるため。
    private func timeline(_ schedule: DayScheduleState, selectedID: CalendarEvent.Identity?) -> some View {
        let key = DayScrollKey(day: schedule.day, isLoaded: schedule.isLoaded, viewportHeight: viewportHeight.rounded())
        return ScrollView {
            DayTimelineCanvas(blocks: schedule.blocks, currentMinute: schedule.currentMinute, selectedID: selectedID) { id in
                viewModel.showDetail(of: id)
            }
        }
        .scrollPosition($scrollPosition)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .task(id: key) {
            guard viewportHeight > 0 else { return }
            let slot = DayTimelineMetrics.reachableSlot(for: schedule.scrollMinute, viewportHeight: viewportHeight)
            // 罫線が枠の上端から上の余白（`topClearance`）だけ下に来る位置。目盛りの文字は罫線の上下にまたがるので、切れない。
            scrollPosition.scrollTo(y: CGFloat(slot) * DayTimelineMetrics.slotHeight)
        }
    }
}

/// 終日の予定 1 件の行。外観に合わせたパレットの色で、薄い背景、枠線、左端の線を描く。
private struct AllDayItemRow: View {
    let item: DayScheduleItem
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let roles = item.color.paletteRoles(colorScheme)
        Button(action: action) {
            HStack(spacing: 6) {
                Text(item.title).font(.callout).lineLimit(1)
                    .opacity(item.isPast ? CalendarPalette.pastTextOpacity : 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4).fill(isSelected ? roles.selectedTintColor : roles.tintColor)
                    .opacity(item.isPast ? CalendarPalette.pastTextOpacity : 1)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(roles.accentColor, lineWidth: 2)
                }
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5).fill(roles.accentColor)
                    .opacity(item.isPast ? CalendarPalette.pastOpacity : 1)
                    .frame(width: 3).padding(.vertical, 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityHint("予定の詳細を開きます")
    }
}


/// 時間軸の中身。上下の余白を含む高さの 1 つの `Canvas` で描き、クリックは全体で 1 つのジェスチャーにして、位置からブロックを求める。
///
/// 予定ごとに View を作らない。VoiceOver かスイッチコントロールが動いているときだけ、ブロックの位置に透明なボタンの要素を置く。
private struct DayTimelineCanvas: View {
    let blocks: [DayScheduleBlock]
    let currentMinute: Int?
    /// 詳細を出している予定。そのブロックを強調する。
    let selectedID: CalendarEvent.Identity?
    let onSelect: (CalendarEvent.Identity) -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled

    var body: some View {
        let blocks = blocks
        let currentMinute = currentMinute
        let selectedID = selectedID
        Canvas { context, _ in
            context.translateBy(x: 0, y: DayTimelineMetrics.verticalInset)
            Self.drawHourGrid(in: &context)
            for block in blocks { Self.draw(block, isSelected: block.id == selectedID, in: &context) }
            if let currentMinute { Self.drawNowLine(minute: currentMinute, in: &context) }
        }
        .frame(height: DayTimelineMetrics.contentHeight)
        .contentShape(Rectangle())
        .onTapGesture { location in
            let point = CGPoint(x: location.x, y: location.y - DayTimelineMetrics.verticalInset)
            // 後に描いたブロックが上に見えるので、後ろから探す。
            if let block = blocks.last(where: { Self.frame(of: $0).contains(point) }) { onSelect(block.id) }
        }
        .overlay(alignment: .topLeading) {
            if isVoiceOverEnabled || isSwitchControlEnabled { accessibilityElements }
        }
    }

    private var accessibilityElements: some View {
        ZStack(alignment: .topLeading) {
            ForEach(blocks) { block in
                let frame = Self.frame(of: block)
                Color.clear
                    .frame(width: frame.width, height: frame.height)
                    .contentShape(Rectangle())
                    .offset(x: frame.minX, y: frame.minY + DayTimelineMetrics.verticalInset)
                    .accessibilityElement()
                    .accessibilityLabel(block.item.accessibilityLabel)
                    .accessibilityHint("予定の詳細を開きます")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onSelect(block.id) }
            }
        }
    }

    /// ブロックの枠。0:00 の罫線を原点とする。
    static func frame(of block: DayScheduleBlock) -> CGRect {
        let columnWidth = DayTimelineMetrics.eventAreaWidth / CGFloat(block.columnCount)
        return CGRect(
            x: DayTimelineMetrics.labelWidth + DayTimelineMetrics.labelGap + CGFloat(block.column) * columnWidth,
            y: CGFloat(block.startMinute) * DayTimelineMetrics.pointsPerMinute + DayTimelineMetrics.blockGap / 2,
            width: columnWidth - DayTimelineMetrics.blockGap,
            height: CGFloat(block.endMinute - block.startMinute) * DayTimelineMetrics.pointsPerMinute - DayTimelineMetrics.blockGap
        )
    }

    private static func drawHourGrid(in context: inout GraphicsContext) {
        let lineX = DayTimelineMetrics.labelWidth + 2
        let lineWidth = DayTimelineMetrics.eventAreaWidth + 6
        for hour in 0..<24 {
            let y = CGFloat(hour) * DayTimelineMetrics.hourHeight
            context.fill(Path(CGRect(x: lineX, y: y, width: lineWidth, height: 1)), with: .color(.primary.opacity(0.1)))
            let label = context.resolve(Text(verbatim: "\(hour):00").font(.caption2.monospacedDigit()).foregroundStyle(Color.secondary))
            context.draw(label, at: CGPoint(x: DayTimelineMetrics.labelWidth, y: y), anchor: .trailing)
        }
    }

    /// ブロック 1 つ。選択中（`isSelected`）なら背景を濃くし、枠線を付ける。高さ 40pt 以上ならタイトル（2 行まで）の下に時刻、それより低ければ 1 行にタイトルと時刻を並べる。
    /// 収まらない文字はブロックの端で切る。
    private static func draw(_ block: DayScheduleBlock, isSelected: Bool, in context: inout GraphicsContext) {
        let frame = frame(of: block)
        let roles = block.item.color.paletteRoles(context.environment.colorScheme)
        let shape = Path(roundedRect: frame, cornerRadius: 4)
        let isPast = block.item.isPast
        context.drawLayer { layer in
            layer.clip(to: shape)
            // 過去のブロックは、薄い背景と文字を薄くし、点と線は少しだけ薄くする。
            layer.drawLayer { background in
                if isPast { background.opacity = CalendarPalette.pastTextOpacity }
                background.fill(shape, with: .color(isSelected ? roles.selectedTintColor : roles.tintColor))
            }
            layer.drawLayer { edge in
                if isPast { edge.opacity = CalendarPalette.pastOpacity }
                edge.fill(Path(CGRect(x: frame.minX, y: frame.minY, width: 3, height: frame.height)), with: .color(roles.accentColor))
            }
            // 詳細を出している予定は、予定の色の枠線（2pt）で強調する。ブロックの形で切るので、外側の半分は切れる。内側に 2pt 入れて描く。
            if isSelected { layer.stroke(Path(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color(roles.accentColor), lineWidth: 2) }
            let textRect = CGRect(x: frame.minX + 8, y: frame.minY + 1, width: max(0, frame.width - 13), height: max(0, frame.height - 2))
            let time = Text(verbatim: block.item.timeText).font(.caption2.monospacedDigit()).foregroundStyle(Color.secondary)
            if frame.height >= 40 {
                let title = layer.resolve(Text(verbatim: block.item.title).font(.callout.weight(.semibold)))
                let lineHeight = layer.resolve(Text(verbatim: "あ").font(.callout.weight(.semibold))).measure(in: textRect.size).height
                let titleSize = title.measure(in: CGSize(width: textRect.width, height: min(textRect.height, lineHeight * 2)))
                layer.drawLayer { titleLayer in
                    if isPast { titleLayer.opacity = CalendarPalette.pastTextOpacity }
                    titleLayer.clip(to: Path(CGRect(origin: textRect.origin, size: CGSize(width: textRect.width, height: titleSize.height))))
                    titleLayer.draw(title, in: CGRect(origin: textRect.origin, size: CGSize(width: textRect.width, height: lineHeight * 2)))
                }
                layer.draw(layer.resolve(time), at: CGPoint(x: textRect.minX, y: textRect.minY + titleSize.height), anchor: .topLeading)
            } else {
                let titleColor = Color.primary.opacity(isPast ? CalendarPalette.pastTextOpacity : 1)
                let line = Text(verbatim: block.item.title).font(.caption.weight(.semibold)).foregroundStyle(titleColor) + Text(verbatim: "  ") + time
                layer.draw(layer.resolve(line), at: textRect.origin, anchor: .topLeading)
            }
        }
    }

    private static func drawNowLine(minute: Int, in context: inout GraphicsContext) {
        let y = CGFloat(minute) * DayTimelineMetrics.pointsPerMinute
        let lineX = DayTimelineMetrics.labelWidth + 2
        context.fill(Path(CGRect(x: lineX, y: y - 0.75, width: DayTimelineMetrics.eventAreaWidth + 6, height: 1.5)), with: .color(.red))
        context.fill(Path(ellipseIn: CGRect(x: lineX - 4, y: y - 4, width: 8, height: 8)), with: .color(.red))
    }
}

