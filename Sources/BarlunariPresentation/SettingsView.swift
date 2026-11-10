import BarlunariApplication
import BarlunariDomain
import SwiftUI

/// 設定画面。`SettingsWindowController` のウインドウに置く。
public struct SettingsView: View {
    public static let width: CGFloat = 480
    public static let height: CGFloat = 460

    public enum Tab: Hashable, Sendable {
        case general, calendars, countdown
    }

    @Bindable private var viewModel: SettingsViewModel
    @State private var selection: Tab

    /// - Parameter initialTab: 最初に開くタブ。スナップショットで各タブを描き分けるために指定できる。
    public init(viewModel: SettingsViewModel, initialTab: Tab = .general) {
        self.viewModel = viewModel
        self._selection = State(initialValue: initialTab)
    }

    public var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem { Label("一般", systemImage: "gearshape") }
                .tag(Tab.general)
            CalendarsSettingsTab(viewModel: viewModel)
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(Tab.calendars)
            CountdownSettingsTab(viewModel: viewModel)
                .tabItem { Label("残り時間", systemImage: "clock") }
                .tag(Tab.countdown)
        }
        // TabView はタブの切り替えの部品を枠の上辺に重ねて描く。周りに余白を取らないと、部品がタイトルバーの区切り線に接し、
        // 枠の線がウインドウの端に重なる。
        .padding(.top, 12)
        .padding([.horizontal, .bottom], 20)
        .frame(width: Self.width, height: Self.height)
        .task { await viewModel.load() }
        .onChange(of: viewModel.changeRevision) { Task { await viewModel.refreshIfChangedElsewhere() } }
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { enabled in Task { await viewModel.setLaunchAtLogin(enabled) } }
                ))
                if let error = viewModel.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Toggle("辞退した予定を表示", isOn: Binding(
                    get: { viewModel.showDeclinedEvents },
                    set: { viewModel.setShowDeclinedEvents($0) }
                ))
                Text("オフにすると、辞退した予定を予定の一覧、日の欄、月のマス目から除きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("週の始まり", selection: Binding(
                    get: { viewModel.firstWeekday },
                    set: { viewModel.setFirstWeekday($0) }
                )) {
                    Text("システムの設定に従う").tag(Weekday?.none)
                    Divider()
                    ForEach(Weekday.allCases, id: \.self) { weekday in
                        Text(weekday.displayName).tag(Weekday?.some(weekday))
                    }
                }
                .pickerStyle(.menu)
                Text("月のマス目とコンパクト表示の週の先頭の曜日です。「システムの設定に従う」では、「言語と地域」の「週の最初の曜日」に従います。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// メニューバーの残り時間に含めるカレンダーを選ぶタブ。階層のある設定なので、スイッチでなくチェックボックスを使う。
private struct CountdownSettingsTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        switch viewModel.calendarsPhase {
        case .idle, .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Form { Section { Text(message).foregroundStyle(.secondary) } }
                .formStyle(.grouped)
        case .guide(let guide):
            Form { Section { Text(guide.message).foregroundStyle(.secondary) } }
                .formStyle(.grouped)
        case .loaded:
            Form {
                Section {
                    Text("チェックを外したカレンダーの予定は、メニューバーの残り時間に含めません。予定の詳細のチェックボックスで、予定ごとに選んだ設定が優先されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.calendarSections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            row(item)
                        }
                    }
                }
                if let error = viewModel.countdownError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func row(_ item: CalendarListItem) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { viewModel.isIncludedInCountdown(item.id) },
                set: { included in Task { await viewModel.setIncludedInCountdown(item.id, isIncluded: included) } }
            )) {
                HStack(spacing: 8) {
                    Circle().fill(item.calendar.color.paletteRoles(colorScheme).accentColor).frame(width: 10, height: 10)
                    Text(item.calendar.name)
                }
            }
            .toggleStyle(.checkbox)
            // 非表示のカレンダーは予定を取得しないので、残り時間にも数えない。
            .disabled(!item.isVisible)
            if !item.isVisible {
                Spacer()
                Text("非表示のため含めません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CalendarsSettingsTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        switch viewModel.calendarsPhase {
        case .idle, .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Form {
                Section { Text(message).foregroundStyle(.secondary) }
                accountsFooter
            }
            .formStyle(.grouped)
        case .guide(let guide):
            Form {
                Section {
                    Text(guide.message).foregroundStyle(.secondary)
                    // カレンダーがないときの操作は、下の「インターネットアカウント」のボタンと同じなので出さない。
                    if guide != .noCalendars {
                        HStack {
                            Spacer()
                            Button(guide.buttonTitle) { Task { await viewModel.perform(guide) } }
                                .disabled(viewModel.isRequestingAccess)
                        }
                    }
                }
                accountsFooter
            }
            .formStyle(.grouped)
        case .loaded:
            Form {
                ForEach(viewModel.calendarSections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            HStack(spacing: 8) {
                                Circle().fill(item.calendar.color.paletteRoles(colorScheme).accentColor).frame(width: 10, height: 10)
                                Text(item.calendar.name)
                                Spacer()
                                Toggle(item.calendar.name, isOn: Binding(
                                    get: { item.isVisible },
                                    set: { isVisible in
                                        Task { await viewModel.setVisibility(of: item.id, isVisible: isVisible) }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                    }
                }
                if let error = viewModel.calendarsError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                accountsFooter
            }
            .formStyle(.grouped)
        }
    }

    /// アカウントの追加と削除、サインインのし直しは、システム設定で行うことの案内。
    private var accountsFooter: some View {
        Section {
            Text("アカウントの追加と削除は、システム設定の「インターネットアカウント」で行います。新しい予定が届かないアカウントは、そこでサインインし直すと同期が再開します。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("「インターネットアカウント」を開く") { viewModel.openInternetAccounts() }
            }
        }
    }
}
