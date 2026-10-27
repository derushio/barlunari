import BarlunariApplication
import BarlunariDomain

/// アカウントのチェックボックスの状態。そのアカウントのカレンダーの表示状態から決まる。
public enum CalendarCheckState: Equatable, Sendable {
    /// すべて表示している。
    case all
    /// すべて非表示にしている。カレンダーを持たないときも含む。
    case none
    /// 一部だけ表示している（混在）。
    case mixed

    /// カレンダーごとの表示状態から求める。
    public init(visibleFlags: some Collection<Bool>) {
        let visibleCount = visibleFlags.filter { $0 }.count
        if visibleCount == 0 {
            self = .none
        } else if visibleCount == visibleFlags.count {
            self = .all
        } else {
            self = .mixed
        }
    }

    /// アカウントのチェックボックスを押したときの切り替え先。すべて表示のときだけすべて非表示にし、それ以外（混在を含む）はすべて表示にする。
    public var nextIsVisible: Bool { self != .all }
}

/// 設定のカレンダータブと、ポップオーバーの表示するカレンダーの一覧の、アカウント 1 件分のセクション。
public struct CalendarAccountSection: Identifiable, Equatable, Sendable {
    public let account: UserAccount
    public let items: [CalendarListItem]

    public var id: AccountID { account.id }
    public var title: String { account.name }

    /// アカウントのチェックボックスの状態。
    public var checkState: CalendarCheckState { CalendarCheckState(visibleFlags: items.map(\.isVisible)) }

    /// アカウントの並び順で、アカウントごとにカレンダーを分ける。カレンダーを持たないアカウントは含まない。
    static func sections(accounts: [UserAccount], items: [CalendarListItem]) -> [CalendarAccountSection] {
        accounts.compactMap { account in
            let accountItems = items.filter { $0.calendar.accountID == account.id }
            return accountItems.isEmpty ? nil : CalendarAccountSection(account: account, items: accountItems)
        }
    }
}
