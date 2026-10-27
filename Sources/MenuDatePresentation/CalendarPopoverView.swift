import AppKit
import MenuDateApplication
import SwiftUI

/// メニューバーのパネルに置く中身。表示モードに従い、月表示かコンパクト表示を出す。
public struct CalendarPopoverView: View {
    public static let width: CGFloat = 300
    /// 予定一覧の高さ。一覧は数十日分を持つので、内容に関わらず固定にする。
    static let agendaHeight: CGFloat = 240

    private let viewModel: CalendarPopoverViewModel
    private let openSettings: @MainActor () -> Void
    private let quit: @MainActor () -> Void
    /// 月表示の大きさを決める、パネルを出すディスプレイの領域。パネルを開くたびに、出す前に更新される。
    private let screenArea: PopoverScreenArea

    /// - Parameters:
    ///   - openSettings: 設定を開く。App 側で設定のウインドウにつなぐ。
    ///   - quit: アプリを終了する。App 側で `NSApp.terminate` につなぐ。
    ///   - screenArea: 月表示の大きさを決める領域。`MenuBarController` がパネルを開くたびに更新する。
    @MainActor public init(
        viewModel: CalendarPopoverViewModel,
        openSettings: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void,
        screenArea: PopoverScreenArea
    ) {
        self.viewModel = viewModel
        self.openSettings = openSettings
        self.quit = quit
        self.screenArea = screenArea
    }

    /// 月表示の大きさを決める領域を固定する。スナップショットと操作ツールが、実行する機械の画面に依らない大きさで出すために使う。
    @MainActor public init(
        viewModel: CalendarPopoverViewModel,
        openSettings: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void,
        visibleFrame: CGRect
    ) {
        self.init(
            viewModel: viewModel, openSettings: openSettings, quit: quit,
            screenArea: PopoverScreenArea(visibleFrame: visibleFrame)
        )
    }

    /// ルートの body が読む ViewModel のプロパティは `changeRevision` だけにする。表示モード、表示月、読み込みの状態、詳細、最終更新の時刻は、
    /// それぞれを読む子の View（`PopoverModeContent`、見出し、`PopoverContent`、フッター）が自分で読む。これらが変わるたびに、ポップオーバー全体の
    /// body が評価し直されて、スクロール中のフレームが間に合わなくなるのを避けるため。ディスプレイの領域も `PopoverModeContent` が読む。
    public var body: some View {
        PopoverModeContent(viewModel: viewModel, openSettings: openSettings, quit: quit, screenArea: screenArea)
            .background(PopoverWindowObserver(viewModel: viewModel))
            .onChange(of: viewModel.changeRevision) { viewModel.reloadIfChangedElsewhere() }
    }
}

/// 表示モードに従い、月表示かコンパクト表示を出す。読む値は `displayMode` と、月表示のときの `screenArea.visibleFrame`。
private struct PopoverModeContent: View {
    let viewModel: CalendarPopoverViewModel
    let openSettings: @MainActor () -> Void
    let quit: @MainActor () -> Void
    let screenArea: PopoverScreenArea

    var body: some View {
        switch viewModel.displayMode {
        case .month:
            MonthCalendarView(viewModel: viewModel, openSettings: openSettings, quit: quit, visibleFrame: screenArea.visibleFrame)
        case .compact:
            CompactPopoverView(viewModel: viewModel, openSettings: openSettings, quit: quit)
        }
    }
}

/// コンパクト表示。幅 300pt の月のマス目と予定一覧。
private struct CompactPopoverView: View {
    let viewModel: CalendarPopoverViewModel
    let openSettings: @MainActor () -> Void
    let quit: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 8) {
            PopoverHeader(viewModel: viewModel)
            MonthGridView(viewModel: viewModel)
            Divider()
            PopoverContent(viewModel: viewModel)
            Divider()
            PopoverFooter(viewModel: viewModel, openSettings: openSettings, quit: quit)
        }
        .padding(12)
        .frame(width: CalendarPopoverView.width)
    }
}

/// 月の見出しと、表示モードの切り替え、月の移動のボタン。読む値は `monthTitle` と `isLoading`。
private struct PopoverHeader: View {
    let viewModel: CalendarPopoverViewModel

    var body: some View {
        HStack(spacing: 4) {
            Text(viewModel.monthTitle).font(.headline).monospacedDigit()
            if viewModel.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
            }
            Spacer()
            CalendarFilterButton(viewModel: viewModel)
            // 幅 300pt の見出しの高さを変えないよう、小さいコントロールにする。
            DisplayModePicker(viewModel: viewModel)
                .controlSize(.mini)
            Button { viewModel.showPreviousMonth() } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("前の月")
            Button("今日") { viewModel.showToday() }
            Button { viewModel.showNextMonth() } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("次の月")
        }
        .buttonStyle(.borderless)
    }
}

/// 表示モードのセグメンテッドコントロール。⌘1 で月表示、⌘2 でコンパクト表示に切り替える。読む値は `displayMode`。
///
/// ラベルは SF Symbols のアイコンで、セグメントごとにツールチップとアクセシビリティのラベルを付ける。
/// キーボードショートカットは、ボタンが必要なので、見えない 2 つのボタンに付ける。
struct DisplayModePicker: View {
    let viewModel: CalendarPopoverViewModel

    var body: some View {
        Picker("表示モード", selection: Binding(
            get: { viewModel.displayMode },
            set: { viewModel.setDisplayMode($0) }
        )) {
            Image(systemName: "calendar")
                .help("月表示 (⌘1)")
                .accessibilityLabel("月表示")
                .tag(CalendarDisplayMode.month)
            Image(systemName: "list.bullet")
                .help("コンパクト表示 (⌘2)")
                .accessibilityLabel("コンパクト表示")
                .tag(CalendarDisplayMode.compact)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .background {
            Group {
                Button("月表示") { viewModel.setDisplayMode(.month) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("コンパクト表示") { viewModel.setDisplayMode(.compact) }
                    .keyboardShortcut("2", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 予定一覧と詳細、または案内とエラーの表示。読む値は `phase` と `isRequestingAccess`。
private struct PopoverContent: View {
    let viewModel: CalendarPopoverViewModel

    var body: some View {
        switch viewModel.phase {
        case .guide(let guide):
            standalone(guide.message, actions: {
                Button(guide.buttonTitle) { Task { await viewModel.perform(guide) } }
                    .disabled(viewModel.isRequestingAccess)
            })
        case .failed(let text):
            standalone(text, actions: { Button("再試行") { viewModel.reload() } })
        case .idle, .loading, .loaded:
            // 予定一覧の View の位置を保つため、案内とエラー以外は、表示するカレンダーの一覧も `AgendaOrDetail` の中で入れ替える。
            AgendaOrDetail(viewModel: viewModel)
        }
    }

    /// 案内とエラーの表示。表示するカレンダーの一覧を開いている間は、代わりに一覧を出す（一覧の中で状況を伝える）。
    @ViewBuilder
    private func standalone<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        if viewModel.isCalendarFilterOpen {
            CalendarFilterView(viewModel: viewModel).frame(height: CalendarPopoverView.agendaHeight)
        } else {
            message(text, actions: actions)
        }
    }

    private func message<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack { actions() }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}

/// 予定一覧と、詳細か表示するカレンダーの一覧を切り替える。読む値は `eventDetail`、`isCalendarFilterOpen`、`isAwaitingFirstLoad`。
/// 詳細は右から入り、戻るときは右へ出る。視差効果を減らす設定では、移動せずにフェードにする。
///
/// 予定一覧の `ScrollView` は詳細を出している間も階層に残す。階層から外すと、戻ったときに作り直されて
/// スクロール位置が先頭に戻るため。詳細は一覧と同じ位置に重ね、一覧は見えなくして操作とアクセシビリティから外す。
/// 一覧が透明で下に透けないので、詳細に背景は敷かない。
///
/// 詳細を開閉しても、スクロール位置を 1pt も動かさないための規則が 2 つある。
/// - 一覧の View に、詳細の開閉で変わる引数、環境の値、`scrollDisabled` を渡さない。変わると `LazyVStack` が、持っている日ごとのセクションをすべて測り直す
///   （今日の付近でも約 3,600 日分で、デバッグビルドで 0.4 秒かかる）。一覧の操作を止めるのは `allowsHitTesting(false)` だけで行う
/// - 一覧の枠の変更（高さ、不透明度）に、詳細の出入りのアニメーションを付けない。付けると、アニメーションの間、一覧の高さの見積もりが揺れて、
///   戻ったときのスクロール位置が 1〜2pt ずれる。詳細の出入りの移動は詳細の View だけに付く
private struct AgendaOrDetail: View {
    let viewModel: CalendarPopoverViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let detail = viewModel.eventDetail
        let isFilterOpen = viewModel.isCalendarFilterOpen
        let isCovered = detail != nil || isFilterOpen
        return ZStack(alignment: .top) {
            agenda
                // 高さを 0 にして、詳細の高さで領域の大きさが決まるようにする。一覧自身は固定の高さを持つので、表示領域は変わらない。
                .frame(height: isCovered ? 0 : nil, alignment: .top)
                .opacity(isCovered ? 0 : 1)
                .allowsHitTesting(!isCovered)
                .accessibilityHidden(isCovered)
                .transaction(value: isCovered) { $0.animation = nil }
            if let detail {
                EventDetailView(detail: detail, onBack: viewModel.closeDetail)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else if isFilterOpen {
                // 表示するカレンダーの一覧は、予定一覧と同じ高さに固定する（開閉でパネルの高さを揺らさない）。
                CalendarFilterView(viewModel: viewModel)
                    .frame(height: CalendarPopoverView.agendaHeight)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .clipped()
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25),
            value: isCovered
        )
        // リンクと「参加」ボタンは ViewModel 経由で URLOpener から開く。
        .environment(\.openURL, OpenURLAction { url in
            viewModel.open(url)
            return .handled
        })
    }

    @ViewBuilder
    private var agenda: some View {
        if viewModel.isAwaitingFirstLoad {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
        } else {
            AgendaScrollView(viewModel: viewModel)
                .frame(height: CalendarPopoverView.agendaHeight)
        }
    }
}

/// 最終更新の時刻と、再読み込み、設定、終了のボタン。読む値は `lastUpdatedText`。
struct PopoverFooter: View {
    let viewModel: CalendarPopoverViewModel
    let openSettings: @MainActor () -> Void
    let quit: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(viewModel.lastUpdatedText ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button { viewModel.reload() } label: { Image(systemName: "arrow.clockwise") }
                .help("再読み込み")
                .accessibilityLabel("再読み込み")
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .help("設定")
                .accessibilityLabel("設定")
            Button("終了") { quit() }
        }
        .buttonStyle(.borderless)
    }
}
