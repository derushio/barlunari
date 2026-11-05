import Foundation
import BarlunariDomain

/// `CalendarEvent.Identity` を、EventKit で予定を探す条件に分解した値。
///
/// `EventID` は `eventIdentifier` と開始日時の UNIX 時刻の秒を `@` でつないだもので、繰り返しの予定の回を区別する。
struct EventKitEventLocator: Equatable {
    let sourceIdentifier: String
    let calendarIdentifier: String
    /// `eventIdentifier`。それがない予定は `calendarItemIdentifier`。
    let identifier: String
    /// 回の開始日時の UNIX 時刻の秒。
    let startSeconds: Int64

    init?(_ identity: CalendarEvent.Identity) {
        let raw = identity.eventID.rawValue
        guard let separator = raw.lastIndex(of: "@"),
              let seconds = Int64(raw[raw.index(after: separator)...]),
              separator != raw.startIndex
        else { return nil }
        sourceIdentifier = identity.accountID.rawValue
        calendarIdentifier = identity.calendarID.rawValue
        identifier = String(raw[..<separator])
        startSeconds = seconds
    }

    /// 回の開始日時を含む、短い取得範囲。
    var searchInterval: DateInterval {
        let start = Date(timeIntervalSince1970: TimeInterval(startSeconds))
        return DateInterval(start: start, duration: 1)
    }

    func matches(identifier candidate: String?, calendarItemIdentifier: String, startDate: Date) -> Bool {
        let candidateIdentifier = candidate.flatMap { $0.isEmpty ? nil : $0 } ?? calendarItemIdentifier
        return candidateIdentifier == identifier && Int64(startDate.timeIntervalSince1970.rounded()) == startSeconds
    }
}
