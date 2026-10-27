import BarlunariDomain
import SwiftUI

/// 連続した日の予定一覧。日ごとの見出しを付ける。
///
/// 日は、一覧の最初の日から数えた番号（`0..<dayCount`）で表す。番号が日ごとのセクションの ID で、プログラムからのスクロールに使う。
/// セクションの View `AgendaSectionView` が、自分の日の表示内容だけを ViewModel から読む。全日分の表示内容は作らない。
/// 各セクションの上端は、スクロールに依存しない内容の座標空間 `coordinateSpaceName` で測り、いま作られているセクションの分をまとめて `onSectionTopsChange` に渡す。
/// 渡す上端は、直前のセクションとの間の余白を含める。上端が余白にかかったとき、見出しが見えている次の日を一番上の日にするため。
/// セクションは `LazyVStack` が必要になったときに作るので、渡す上端は作られているセクションだけである。作られなくなったセクションの古い上端は残らない。
struct AgendaListView: View {
    /// 内容の座標空間の名前。原点は一覧の左上で、スクロールしても動かない。
    nonisolated static let coordinateSpaceName = "agendaContent"
    /// 日ごとのセクションの間の余白。
    nonisolated static let sectionSpacing: CGFloat = 10

    let viewModel: CalendarPopoverViewModel
    let dayCount: Int
    /// 測ったセクションの上端を渡す先。引数を参照にして、親の body が再評価されても、この View の body を再評価させない。
    let geometry: AgendaScrollGeometry

    var body: some View {
        // 表示に近いセクションだけを作る。全日分を作ると、スクロールのたびのレイアウトと測定が日数に比例して増える。
        // 作る前のセクションの高さは推定なので、番号を指定したスクロールは `AgendaScrollView` が位置を測って合わせ直す。
        LazyVStack(alignment: .leading, spacing: Self.sectionSpacing) {
            ForEach(0..<dayCount, id: \.self) { index in
                AgendaSectionView(viewModel: viewModel, index: index)
            }
        }
        .coordinateSpace(.named(Self.coordinateSpaceName))
        .onPreferenceChange(AgendaSectionTopsKey.self) { geometry.replace($0) }
        .scrollTargetLayout()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 1 日分のセクション。自分の日の表示内容だけを ViewModel から読む。
private struct AgendaSectionView: View {
    let viewModel: CalendarPopoverViewModel
    let index: Int

    var body: some View {
        if let section = viewModel.agendaSection(at: index) {
            VStack(alignment: .leading, spacing: 4) {
                // 行はホバーの背景のために内側に余白を持つ。見出しと文は同じ幅だけ内側に寄せて、左端をそろえる。
                HStack(spacing: 6) {
                    Text(section.title).font(.caption.weight(.semibold))
                    if let label = section.relativeLabel {
                        Text(label).font(.caption2.weight(.medium)).foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, AgendaRowView.horizontalInset)
                if !section.isLoaded {
                    Text("読み込み中…").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, AgendaRowView.horizontalInset)
                } else if section.rows.isEmpty {
                    Text("予定はありません").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, AgendaRowView.horizontalInset)
                } else {
                    ForEach(section.rows) { row in
                        AgendaRowView(
                            state: row,
                            onOpenMeeting: { viewModel.openMeeting(of: row) },
                            onShowDetail: { viewModel.showDetail(of: row) }
                        )
                    }
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AgendaSectionTopsKey.self,
                        value: [index: proxy.frame(in: .named(AgendaListView.coordinateSpaceName)).minY - AgendaListView.sectionSpacing]
                    )
                }
            }
        }
    }
}

struct AgendaRowView: View {
    /// ホバーの背景を行の外側に広げるための、行の内側の左右の余白。
    static let horizontalInset: CGFloat = 6

    let state: AgendaRowState
    let onOpenMeeting: () -> Void
    let onShowDetail: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onShowDetail) {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(state.color?.swiftUIColor ?? Color.gray)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.timeText).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        Text(state.title).font(.callout).lineLimit(2)
                        if let location = state.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Self.horizontalInset)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(isHovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .pointerStyle(.link)
            .accessibilityHint("予定の詳細を開きます")

            if state.hasMeetingURL {
                Button("参加", action: onOpenMeeting)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(state.isPast ? 0.45 : 1)
    }
}

/// いま作られているセクションの上端。日の番号をキーに持つ。
private struct AgendaSectionTopsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
