import BarlunariDomain
import SwiftUI

/// 月表示。予定をマス目の中に並べた、大きな 1 枚のカレンダーと、その右の日の欄と詳細の列。
///
/// 左の列は、見出し、曜日の行、マス目、フッターを縦に並べる。見出し、曜日の行、フッターの高さは固定で、マス目に使える高さを `MonthPopoverSizing` が求める。
/// 右の日の欄（`MonthDayPane`）と詳細の列（`MonthDetailColumn`。可視領域が狭いときは出さない）は、1pt の区切り線で分け、重ねない。案内とエラーは、マス目の上の中央に重ねる。
/// この View は ViewModel の値を読まない。マス目の View にも、日の欄の状態で変わる引数や環境の値を渡さない
/// （渡すと、日の欄を切り替えるたびにマス目の全行が評価し直される）。
struct MonthCalendarView: View {
    let viewModel: CalendarPopoverViewModel
    let openSettings: @MainActor () -> Void
    let quit: @MainActor () -> Void
    let visibleFrame: CGRect

    var body: some View {
        let size = MonthPopoverSizing.size(visibleFrame: visibleFrame)
        let rowHeight = MonthPopoverSizing.rowHeight(popoverHeight: size.height)
        let gridHeight = MonthPopoverSizing.gridHeight(popoverHeight: size.height)
        let layout = MonthPopoverSizing.layout(visibleFrame: visibleFrame)
        let gridWidth = MonthPopoverSizing.gridWidth(popoverWidth: size.width, layout: layout)
        let paneContentMaxHeight = size.height - MonthPopoverSizing.dayPaneChromeHeight
        HStack(spacing: 0) {
            VStack(spacing: MonthPopoverSizing.sectionSpacing) {
                MonthHeader(viewModel: viewModel)
                    .frame(height: MonthPopoverSizing.headerHeight)
                WeekdayHeaderRow(viewModel: viewModel)
                    .frame(height: MonthPopoverSizing.weekdayRowHeight)
                ZStack(alignment: .topLeading) {
                    WeekScrollView(
                        viewModel: viewModel, rowHeight: rowHeight,
                        viewportHeight: rowHeight * CGFloat(MonthPopoverSizing.visibleWeekCount),
                        preparesMonthEvents: true
                    ) { index in
                        MonthWeekRowView(viewModel: viewModel, weekIndex: index, rowHeight: rowHeight)
                    }
                    MonthStatusOverlay(viewModel: viewModel)
                }
                .frame(height: gridHeight, alignment: .top)
                .clipped()
                Divider()
                // 「終了」が日の欄との区切り線に接しないよう、日の欄の左の余白と同じだけ離す。
                PopoverFooter(viewModel: viewModel, openSettings: openSettings, quit: quit)
                    .padding(.trailing, MonthPopoverSizing.dayPaneLeadingInset)
                    .frame(height: MonthPopoverSizing.footerHeight)
            }
            .frame(width: gridWidth)
            paneDivider
            MonthDayPane(viewModel: viewModel, showsDetail: layout == .twoColumn, contentMaxHeight: paneContentMaxHeight)
                .frame(width: MonthPopoverSizing.dayPaneWidth)
            if layout == .threeColumn {
                paneDivider
                MonthDetailColumn(viewModel: viewModel, contentMaxHeight: paneContentMaxHeight)
                    .frame(width: MonthPopoverSizing.detailColumnWidth)
            }
        }
        .padding(MonthPopoverSizing.contentPadding)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// 列の間の区切り線。
private var paneDivider: some View {
    Rectangle()
        .fill(Color.primary.opacity(0.15))
        .frame(width: MonthPopoverSizing.paneDividerWidth)
}

/// 月表示の見出し。月、読み込み中の表示、表示モードの切り替え、前の月、今日、次の月。読む値は `monthTitle` と `isLoading`。
private struct MonthHeader: View {
    let viewModel: CalendarPopoverViewModel

    var body: some View {
        HStack(spacing: 8) {
            Text(viewModel.monthTitle).font(.title3.weight(.semibold)).monospacedDigit()
            if viewModel.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 18, height: 18)
            }
            Spacer()
            CalendarFilterButton(viewModel: viewModel)
                .buttonStyle(.bordered)
            DisplayModePicker(viewModel: viewModel)
            HStack(spacing: 4) {
                Button { viewModel.showPreviousMonth() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("前の月")
                Button("今日") { viewModel.showToday() }
                Button { viewModel.showNextMonth() } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("次の月")
            }
            .buttonStyle(.bordered)
        }
    }
}

/// 案内（許可の依頼など）とエラーを、マス目の上の中央に重ねて出す。読む値は `phase` と `isRequestingAccess`。
private struct MonthStatusOverlay: View {
    let viewModel: CalendarPopoverViewModel

    var body: some View {
        switch viewModel.phase {
        case .guide(let guide):
            message(guide.message) {
                Button(guide.buttonTitle) { Task { await viewModel.perform(guide) } }
                    .disabled(viewModel.isRequestingAccess)
            }
        case .failed(let text):
            message(text) { Button("再試行") { viewModel.reload() } }
        case .idle, .loading, .loaded:
            EmptyView()
        }
    }

    private func message<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack { actions() }
        }
        .padding(20)
        .frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.15)))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
