import AppKit
import BarlunariApplication
import BarlunariDomain
import SwiftUI

/// 見出しの、表示するカレンダーの一覧を開閉するボタン。読む値は `isCalendarFilterOpen`。
///
/// 開いている間は塗りつぶしのシンボルにして、形でも状態を伝える。
struct CalendarFilterButton: View {
    let viewModel: CalendarPopoverViewModel

    var body: some View {
        let isOpen = viewModel.isCalendarFilterOpen
        Button { viewModel.toggleCalendarFilter() } label: {
            Image(systemName: isOpen ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("表示するカレンダー")
        .accessibilityLabel("表示するカレンダー")
        .accessibilityValue(isOpen ? "開いています" : "閉じています")
    }
}

/// 表示するカレンダーの一覧。アカウントごとにまとめ、アカウントとカレンダーのチェックボックスで表示と非表示を切り替える。
///
/// 月表示は右側のパネル、コンパクト表示は予定一覧の位置に出す。別のポップオーバーやメニューは重ねない。
/// チェックを 1 つ切り替えても閉じず、閉じるボタンか Esc で閉じる。読む値は一覧の状態だけ。
struct CalendarFilterView: View {
    let viewModel: CalendarPopoverViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("表示するカレンダー").font(.headline)
                Spacer()
                Button { viewModel.closeCalendarFilter() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("閉じる")
                    .accessibilityLabel("表示するカレンダーを閉じる")
            }
            content
            if let error = viewModel.calendarFilterError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand { viewModel.closeCalendarFilter() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.calendarFilterPhase {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
        case .unavailable(let text):
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.calendarFilterSections) { section in
                        CalendarFilterAccountGroup(viewModel: viewModel, section: section)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// アカウント 1 件分。見出しのチェックボックスでアカウントのカレンダーをまとめて切り替え、カレンダーごとのチェックボックスを並べる。
private struct CalendarFilterAccountGroup: View {
    let viewModel: CalendarPopoverViewModel
    let section: CalendarAccountSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CheckboxButton(title: section.title, accessibilityName: section.title, state: section.checkState, isBold: true) {
                let isVisible = section.checkState.nextIsVisible
                Task { await viewModel.setVisibility(ofAccount: section.id, isVisible: isVisible) }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(section.items) { item in
                    CheckboxButton(
                        title: item.calendar.name, accessibilityName: item.calendar.name,
                        swatch: item.calendar.color, state: item.isVisible ? .all : .none, isBold: false
                    ) {
                        Task { await viewModel.setVisibility(of: item.id, isVisible: !item.isVisible) }
                    }
                }
            }
            .padding(.leading, 20)
        }
        .accessibilityElement(children: .contain)
    }
}

/// チェックボックス。混在の状態を持てる。SwiftUI の `Toggle` は macOS で混在の状態を持てないので、`NSButton` を使う。
/// カレンダーごとのチェックボックスも、同じ `NSButton` にそろえる（操作ツールの合成したクリックに `Toggle` が反応しなかったため）。
///
/// 押したときの切り替え先は、ボタンの状態の自動の巡回ではなく、呼び出し側が決める（混在のときはすべて表示）。
/// ボタンの状態は、押した直後にいったんモデルの状態へ戻し、モデルが変わったら `updateNSView` で合わせる。
private struct CheckboxButton: NSViewRepresentable {
    let title: String
    /// VoiceOver に読ませる名前。`title` が空でも、チェックボックスの名前になる。
    let accessibilityName: String
    /// タイトルの前に出す、カレンダーの色の丸。
    var swatch: CalendarColor?
    let state: CalendarCheckState
    let isBold: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.allowsMixedState = true
        button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: isBold ? .semibold : .regular)
        button.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if isBold { button.setAccessibilityHelp("このアカウントのカレンダーをまとめて表示・非表示にします") }
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.state = state
        context.coordinator.action = action
        if let swatch {
            button.attributedTitle = Self.attributedTitle(title, swatch: swatch, isBold: isBold)
        } else if button.title != title {
            button.title = title
        }
        button.setAccessibilityLabel(accessibilityName)
        button.state = state.buttonState
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSButton, context: Context) -> CGSize? {
        let size = button.intrinsicContentSize
        return CGSize(width: min(size.width, proposal.width ?? size.width), height: size.height)
    }

    /// 色の丸の画像を文字の前に付けたタイトル。
    private static func attributedTitle(_ title: String, swatch: CalendarColor, isBold: Bool) -> NSAttributedString {
        let diameter: CGFloat = 10
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor(
                srgbRed: CGFloat(swatch.red) / 255, green: CGFloat(swatch.green) / 255, blue: CGFloat(swatch.blue) / 255, alpha: 1
            ).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -1, width: diameter, height: diameter)
        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: "  " + title))
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: isBold ? .semibold : .regular)
        result.addAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: NSRange(location: 0, length: result.length))
        return result
    }

    @MainActor
    final class Coordinator: NSObject {
        var state: CalendarCheckState = .none
        var action: () -> Void = {}

        @objc func clicked(_ sender: NSButton) {
            sender.state = state.buttonState
            action()
        }
    }
}

private extension CalendarCheckState {
    var buttonState: NSControl.StateValue {
        switch self {
        case .all: .on
        case .none: .off
        case .mixed: .mixed
        }
    }
}
