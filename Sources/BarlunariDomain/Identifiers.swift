import Foundation

/// 空でない文字列をラップする識別子の共通検証。
private func validatedIdentifier(_ rawValue: String) throws -> String {
    guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DomainError.emptyIdentifier
    }
    return rawValue
}

public struct CalendarID: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        self.rawValue = try validatedIdentifier(rawValue)
    }

    public static func < (lhs: CalendarID, rhs: CalendarID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}

public struct EventID: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        self.rawValue = try validatedIdentifier(rawValue)
    }

    public static func < (lhs: EventID, rhs: EventID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}

/// アカウントの識別子。OS が発行し、アカウントごとに変わらない ID を使う。
public struct AccountID: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        self.rawValue = try validatedIdentifier(rawValue)
    }

    public static func < (lhs: AccountID, rhs: AccountID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}
