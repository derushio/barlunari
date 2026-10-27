import Foundation

/// カレンダーを持つアカウント。同一性は `id` で判定する。
///
/// 名前は表示のために持つ。変更されうるため、同一性には使わない。
public struct UserAccount: Sendable, Hashable, Identifiable {
    public let id: AccountID
    public let name: String

    /// 名前の前後の空白は取り除く。空にはできない。
    public init(id: AccountID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyAccountName }
        self.id = id
        self.name = trimmed
    }

    /// `name` は更新されうるため、同一性は `id` だけで判定する。
    public static func == (lhs: UserAccount, rhs: UserAccount) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
