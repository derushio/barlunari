import BarlunariApplication
import BarlunariDomain
import SwiftUI

/// 設定画面。`SettingsWindowController` のウインドウに置く。
public struct SettingsView: View {
    public static let width: CGFloat = 480
    public static let height: CGFloat = 460

    public enum Tab: Hashable, Sendable {
        case general, calendars
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
        }
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
        }
        .formStyle(.grouped)
    }
}

private struct CalendarsSettingsTab: View {
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
                                Circle().fill(item.calendar.color.swiftUIColor).frame(width: 10, height: 10)
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
