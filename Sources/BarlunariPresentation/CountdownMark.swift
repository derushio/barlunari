import BarlunariDomain

/// 予定の一覧（予定一覧、日の欄、月のマス目）に付ける、メニューバーの残り時間の対象かどうかの記号。
///
/// 予定ごとの選択が、その予定の既定の値（カレンダーの設定込み。`CountdownTargetPolicy.isTargetByDefault(_:)`）と違う予定にだけ付ける。
/// 既定どおりの予定は `none` で、記号を出さない。カレンダーごと含めないカレンダーの予定にも、一律には付けない。
/// 辞退した予定は、設定に従って記号を付ける。辞退した予定を数えないのは `NextEventCountdown` が決める。
public enum CountdownMark: Equatable, Sendable {
    case none
    /// 既定で対象の予定（含めるカレンダーの時刻付きの予定）を、対象から外した。
    case excluded
    /// 既定で対象外の予定（終日の予定、含めないカレンダーの予定）を、対象にした。
    case included

    init(_ event: CalendarEvent, policy: CountdownTargetPolicy) {
        let isTarget = policy.isTarget(event)
        if isTarget == policy.isTargetByDefault(event) {
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
