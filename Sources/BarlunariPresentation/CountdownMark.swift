import BarlunariDomain

/// 予定の一覧（予定一覧、日の欄、月のマス目）に付ける、メニューバーの残り時間の対象かどうかの記号。
///
/// 既定の設定（時刻付きは対象、終日は対象外）と違う設定にした予定にだけ付ける。既定どおりの予定は `none` で、記号を出さない。
/// 辞退した予定は、設定に従って記号を付ける。辞退した予定を数えないのは `NextEventCountdown` が決める。
public enum CountdownMark: Equatable, Sendable {
    case none
    /// 既定で対象の時刻付きの予定を、対象から外した。
    case excluded
    /// 既定で対象外の終日の予定を、対象にした。
    case included

    init(_ event: CalendarEvent, settings: CountdownTargetSettings) {
        let isTarget = settings.isTarget(event)
        if isTarget == CountdownTargetSettings.isTargetByDefault(event.schedule) {
            self = .none
        } else {
            self = isTarget ? .included : .excluded
        }
    }

    /// 記号の SF Symbol の名前。`none` は `nil`。詳細の「メニューバーの残り時間に含める」と同じ意味の記号である。
    public var symbolName: String? {
        switch self {
        case .none: nil
        case .excluded: "clock.badge.xmark"
        case .included: "clock.badge.checkmark"
        }
    }

    /// VoiceOver で読む文字。`none` は `nil`。
    public var label: String? {
        switch self {
        case .none: nil
        case .excluded: "残り時間の対象外"
        case .included: "残り時間の対象"
        }
    }
}
