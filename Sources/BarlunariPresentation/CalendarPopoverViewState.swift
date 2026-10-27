import BarlunariDomain

/// 月のマス目の 1 日分の表示内容。
public struct DayCellState: Identifiable, Equatable, Sendable {
    public enum WeekdayKind: Equatable, Sendable {
        case sunday, saturday, weekday
    }

    public let day: CalendarDay
    public let isInMonth: Bool
    public let isToday: Bool
    public let isSelected: Bool
    /// 選べる日か。マス目が表示できる月の日だけ選べる。端の行に見える、表示できない月の日は選べない。
    public let isSelectable: Bool
    public let weekdayKind: WeekdayKind
    /// 予定があるカレンダーの色。ドットに出す最大 3 色だけを持つ。
    public let dotColors: [CalendarColor]
    public let accessibilityLabel: String

    public var id: CalendarDay { day }
    public var number: Int { day.day }
}

/// 月表示のマスの層が描く 1 日分の表示内容。表示月、選択日、予定を持たない。
public struct MonthDayState: Equatable, Sendable {
    public let day: CalendarDay
    public let isToday: Bool
    /// 選べる日か。選べない日は、予定を取得していない。
    public let isSelectable: Bool
    public let weekdayKind: DayCellState.WeekdayKind

    public var number: Int { day.day }
}

/// 月表示で VoiceOver に見せる、日のボタンの内容。
public struct DayAccessibilityState: Identifiable, Equatable, Sendable {
    public let day: CalendarDay
    /// 例は `10月24日(土)`。
    public let label: String
    public let isSelected: Bool
    public let isSelectable: Bool

    public var id: CalendarDay { day }
}

/// 月表示の 1 週分の表示内容。
public struct MonthWeekState: Equatable, Sendable {
    /// 7 日分のマスの表示内容。`CalendarPopoverViewModel.weekCells(at:)` と同じである。
    public let cells: [DayCellState]
    /// 7 日分の予定の配置。
    public let layout: MonthWeekLayout
}

/// 予定一覧の 1 行の表示内容。
public struct AgendaRowState: Identifiable, Equatable, Sendable {
    public let id: CalendarEvent.Identity
    public let color: CalendarColor?
    /// `10:00〜10:15` か「終日」。
    public let timeText: String
    public let title: String
    public let location: String?
    public let isPast: Bool
    public let hasMeetingURL: Bool
}

/// 予定一覧の 1 日分。
public struct AgendaSectionState: Identifiable, Equatable, Sendable {
    public let day: CalendarDay
    /// `10月24日(土)`。
    public let title: String
    /// 今日なら「今日」、翌日なら「明日」。
    public let relativeLabel: String?
    public let rows: [AgendaRowState]
    /// 予定を取得済みの日か。`false` の日は予定がないのではなく未取得なので、「予定はありません」を出してはいけない。
    public let isLoaded: Bool

    public var id: CalendarDay { day }
}

/// 日の欄のスケジュールに出す予定 1 件。終日の予定と、時間軸のブロックで共通である。
public struct DayScheduleItem: Identifiable, Equatable, Sendable {
    public let id: CalendarEvent.Identity
    public let color: CalendarColor?
    /// タイトルがなければ「(タイトルなし)」。
    public let title: String
    /// `10:00〜10:15`、`〜12:00`、`23:00〜`、「終日」。
    public let timeText: String
    public let calendarName: String?
    public let isPast: Bool

    /// VoiceOver に読ませる文。時刻、タイトル、カレンダーの名前の順。
    public var accessibilityLabel: String {
        [timeText, title, calendarName].compactMap { $0 }.joined(separator: "、")
    }
}

/// 日の欄の時間軸に置くブロック 1 つ。位置は開始時刻で決め、重なる予定は列で分ける（`DayTimelineLayout`）。
public struct DayScheduleBlock: Identifiable, Equatable, Sendable {
    public let item: DayScheduleItem
    /// 0 時からの分。
    public let startMinute: Int
    /// 0 時からの分。表示上の長さの下限を持たせてある。
    public let endMinute: Int
    public let column: Int
    public let columnCount: Int

    public var id: CalendarEvent.Identity { item.id }
}

/// 日の欄に出す、1 日のスケジュール。
public struct DayScheduleState: Equatable, Sendable {
    public let day: CalendarDay
    /// `10月24日(土)`。
    public let title: String
    /// 今日なら「今日」、翌日なら「明日」。
    public let relativeLabel: String?
    public let isToday: Bool
    /// 予定を取得済みの日か。`false` の日は予定がないのではなく未取得なので、「予定はありません」を出してはいけない。
    public let isLoaded: Bool
    /// 許可の案内かエラーで、予定を表示できないか。
    public let isUnavailable: Bool
    /// 終日の予定と、その日が丸ごと埋まる時刻付きの予定。
    public let allDay: [DayScheduleItem]
    /// 時刻付きの予定。開始の早い順。
    public let blocks: [DayScheduleBlock]
    /// 今日のときの現在時刻（0 時からの分）。今日でなければ `nil`。
    public let currentMinute: Int?
    /// 開いたときに一番上にする時刻（0 時からの分、30 分の単位）。`DayScheduleScroll.targetMinute` が決める。
    public let scrollMinute: Int

    public var id: CalendarDay { day }
    public var isEmpty: Bool { allDay.isEmpty && blocks.isEmpty }
}

/// 予定一覧のスクロールを求める要求。
public struct AgendaScrollRequest: Equatable, Sendable {
    /// 一番上に置く日。
    public let day: CalendarDay
    /// 同じ日を続けて求めても別の要求として区別するための通し番号。
    public let serial: Int
}

/// 月のマス目のスクロールを求める要求。
public struct GridScrollRequest: Equatable, Sendable {
    /// 一番上に置く週の番号。
    public let weekIndex: Int
    /// 同じ週を続けて求めても別の要求として区別するための通し番号。
    public let serial: Int
}
