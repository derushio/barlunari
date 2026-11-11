import SwiftUI
import BarlunariDomain

/// 詳細の出欠の回答欄から呼ぶ操作。View に ViewModel を持たせず、押されたときの処理だけを渡す。
struct EventDetailActions {
    var respond: (AttendanceResponse) -> Void = { _ in }
    var openInCalendar: () -> Void = {}
    var setIncludedInCountdown: (Bool) -> Void = { _ in }

    @MainActor
    init(_ viewModel: CalendarPopoverViewModel) {
        respond = { response in Task { await viewModel.respond(response) } }
        setIncludedInCountdown = { included in Task { await viewModel.setIncludedInCountdown(included) } }
        openInCalendar = { Task { await viewModel.openDetailInCalendarApp() } }
    }

    init() {}
}

/// 予定一覧の領域と入れ替えて出す、予定の詳細。
///
/// リンクと「参加」ボタンは環境の `openURL` で開く。`CalendarPopoverView` が `openURL` を ViewModel に向ける。
struct EventDetailView: View {
    /// 詳細の高さの上限。これを超えたらスクロールする。一覧に戻るボタンは含まない。
    static let maxHeight: CGFloat = 300

    let detail: EventDetailState
    @Environment(\.colorScheme) private var colorScheme
    let onBack: () -> Void
    var actions = EventDetailActions()
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
                    .fill(detail.color.paletteRoles(colorScheme).fillColor)
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
            countdownRow
            if let location = detail.location {
                infoRow("mappin.and.ellipse") { Text(location).textSelection(.enabled) }
            }
            if let rsvp = detail.rsvp {
                rsvpRow(rsvp)
            } else if let attendanceText = detail.attendanceText {
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

    /// 残り時間の対象のチェックボックスの行。アイコンは出さず、四角をほかの行のアイコンの列（幅 `iconColumnWidth`）の中心に置き、
    /// タイトルをほかの行の文字と同じ x から始める。四角とタイトルは 1 つの `Toggle` で、タイトルを押しても切り替わる。
    private var countdownRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if detail.canBeCountdownTarget {
                Toggle(isOn: Binding(get: { detail.includedInCountdown }, set: { actions.setIncludedInCountdown($0) })) {
                    Text("メニューバーの残り時間に含める")
                        .font(.callout)
                        .padding(.leading, Self.countdownTitleLeadingPadding)
                }
                .toggleStyle(.checkbox)
                // チェックボックスの部品は文字 1 行より下に高い。その分を打ち消し、行の間隔をほかの行と同じにする。
                .padding(.bottom, -Self.checkboxExtraHeight)
            } else {
                // 操作できないチェックボックスは出さず、含めない理由を文で示す。
                Text("終日の予定は残り時間に含めません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.iconColumnWidth + Self.iconTextSpacing)
            }
            if detail.isDeclined {
                Text("辞退した予定は残り時間に含めません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.iconColumnWidth + Self.iconTextSpacing)
            }
            if detail.isCalendarExcludedFromCountdown {
                // チェックがオンの予定は、カレンダーの設定より予定ごとの選択が優先されて数えている。文がチェックの状態と食い違って読めないよう、状態ごとに出し分ける。
                Text(
                    detail.includedInCountdown
                        ? "このカレンダーは設定の「残り時間」タブで含めない設定ですが、この予定は個別に含めています。"
                        : "このカレンダーは設定の「残り時間」タブで含めない設定です。チェックすると、この予定だけ含めます。"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.iconColumnWidth + Self.iconTextSpacing)
            }
        }
    }

    /// 情報の行のアイコンの列の幅と、アイコンと文字の間隔。
    private static let iconColumnWidth: CGFloat = 16
    private static let iconTextSpacing: CGFloat = 6
    /// チェックボックスの四角の右からタイトルまでの標準の間隔を補い、タイトルを文字の列に揃える。
    private static let countdownTitleLeadingPadding: CGFloat = 2
    /// チェックボックスの部品の高さが、ほかの行の文字 1 行の高さを下に超える量。
    private static let checkboxExtraHeight: CGFloat = 2.5

    /// 出欠の回答欄。現在の出欠のボタンは塗りの記号と濃い背景で出し、色が見えなくても区別できるようにする。
    private func rsvpRow(_ rsvp: EventRSVPState) -> some View {
        infoRow("person.crop.circle.badge.checkmark") {
            VStack(alignment: .leading, spacing: 6) {
                Text(rsvp.current == .needsAction ? "出欠（未回答）" : "出欠")
                HStack(spacing: 6) {
                    ForEach(AttendanceResponse.allCases, id: \.self) { response in
                        rsvpButton(response, isSelected: rsvp.current == response.attendance)
                    }
                    if rsvp.isResponding { ProgressView().controlSize(.small) }
                }
                .disabled(rsvp.isResponding)
                if let message = rsvp.errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(message)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: actions.openInCalendar) {
                        Label("カレンダーで開く", systemImage: "calendar")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func rsvpButton(_ response: AttendanceResponse, isSelected: Bool) -> some View {
        Button { actions.respond(response) } label: {
            Label(response.title, systemImage: response.symbol(isSelected: isSelected))
        }
        .buttonStyle(RSVPButtonStyle(isSelected: isSelected))
        .accessibilityLabel(response.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        HStack(alignment: .firstTextBaseline, spacing: Self.iconTextSpacing) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: Self.iconColumnWidth)
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

/// 出欠の回答ボタン。選んでいるボタンは、塗りつぶした背景、太い文字、塗りの記号で区別する。
/// ウインドウが非アクティブでも見た目が変わらないよう、標準のボタンの装飾は使わない。
private struct RSVPButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(isSelected ? .bold : .regular))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(configuration.isPressed ? 0.3 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(isSelected ? 0 : 0.5), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.6)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
