import SwiftUI

/// 予定一覧の領域と入れ替えて出す、予定の詳細。
///
/// リンクと「参加」ボタンは環境の `openURL` で開く。`CalendarPopoverView` が `openURL` を ViewModel に向ける。
struct EventDetailView: View {
    /// 詳細の高さの上限。これを超えたらスクロールする。一覧に戻るボタンは含まない。
    static let maxHeight: CGFloat = 300

    let detail: EventDetailState
    let onBack: () -> Void
    /// 内容の高さの上限。コンパクト表示は既定の `maxHeight`、月表示の右側のパネルは、パネルの高さに合わせて渡す。
    var contentMaxHeight: CGFloat = Self.maxHeight
    /// 戻るボタンの文。コンパクト表示は予定一覧へ、月表示は元の画面へ戻る。
    var backTitle = "予定一覧"
    var backAccessibilityLabel = "予定一覧に戻る"
    /// 戻るボタンの代わりに、右上に閉じるボタン（xmark）を出す。月表示の詳細の列で使い、`backAccessibilityLabel` がボタンのラベルになる。
    var showsCloseButton = false

    @Environment(\.openURL) private var openURL
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsCloseButton {
                HStack {
                    Spacer()
                    Button(action: onBack) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("閉じる")
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel(backAccessibilityLabel)
                }
            } else {
                Button(action: onBack) {
                    Label(backTitle, systemImage: "chevron.left").font(.callout)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(backAccessibilityLabel)
            }

            ScrollView {
                content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 1), contentMaxHeight))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onExitCommand(perform: onBack)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(detail.color?.swiftUIColor ?? Color.gray)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                Text(detail.title)
                    .font(.headline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)

            infoRow("clock") { Text(detail.dateText).textSelection(.enabled) }
            if let calendarText = detail.calendarText {
                infoRow("calendar") { Text(calendarText).textSelection(.enabled) }
            }
            if let location = detail.location {
                infoRow("mappin.and.ellipse") { Text(location).textSelection(.enabled) }
            }
            if let attendanceText = detail.attendanceText {
                infoRow("person.crop.circle.badge.checkmark") { Text("出欠: \(attendanceText)") }
            }
            if let detailURL = detail.detailURL {
                infoRow("link") {
                    Link(destination: detailURL) {
                        Text(detailURL.absoluteString)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }
            if let meetingURL = detail.meetingURL {
                Button { openURL(meetingURL) } label: {
                    Label("参加", systemImage: "video")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            if !detail.participants.isEmpty { participants }
            if let notes = detail.notes {
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("メモ")
                    Text(notes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("参加者 \(detail.participants.count)人")
            ForEach(detail.participants) { participant in
                ParticipantRowView(state: participant)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func infoRow<Content: View>(_ systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            content()
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ParticipantRowView: View {
    let state: ParticipantRowState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(symbolColor)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(state.displayName).font(.callout).lineLimit(1).truncationMode(.middle)
                    if state.isOrganizer { badge("主催者") }
                    if state.isCurrentUser { badge("自分") }
                }
                if let emailAddress = state.emailAddress {
                    Text(emailAddress).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if let text = state.attendanceText {
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))
            .fixedSize()
    }

    private var symbol: String {
        switch state.attendance {
        case .accepted: "checkmark.circle.fill"
        case .tentative: "questionmark.circle.fill"
        case .declined: "xmark.circle.fill"
        case .needsAction: "circle.dashed"
        case .notApplicable: "person.circle"
        }
    }

    private var symbolColor: Color {
        switch state.attendance {
        case .accepted: .green
        case .tentative: .orange
        case .declined: .red
        case .needsAction, .notApplicable: .secondary
        }
    }
}
