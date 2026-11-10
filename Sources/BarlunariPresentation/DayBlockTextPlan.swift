import CoreGraphics

/// 日の欄の時間軸のブロックに、タイトルと時刻をどう並べるかの計画。
///
/// 文字を字の途中で切らないよう、幅と高さを測り、収まる組み合わせを選ぶ。測る処理（`Measure`）は呼び出し側が渡す。
/// 1 行のブロックは「タイトル 開始〜終了」→「タイトル 開始」→「タイトル」の順、2 行以上のブロックは時刻を
/// 「開始〜終了」→「開始」→出さない、の順に選び、タイトルは残りの高さに入る行数まで「…」で切り詰める。
struct DayBlockTextPlan: Equatable {
    enum Mode: Equatable {
        /// タイトルの下に時刻を出す。
        case stacked
        /// 1 行にタイトルと時刻を並べる。
        case singleLine
        /// 1 行に満たない高さ。小さい文字でタイトルだけを出す。
        case minimal
    }

    /// 測る文字の種類。
    enum Role: Hashable {
        /// 2 行以上のブロックのタイトル。
        case stackedTitle
        /// 時刻。
        case time
        /// 1 行のブロックのタイトル。
        case lineTitle
        /// 1 行に満たない高さのブロックのタイトル。文字の大きさは `fontSize` で決める。
        case tinyTitle(fontSize: CGFloat)
    }

    /// 文字を、`width` で折り返したときの大きさ。`width` が十分大きければ 1 行の大きさ。
    typealias Measure = (_ text: String, _ role: Role, _ width: CGFloat) -> CGSize

    let mode: Mode
    /// 収まるように切り詰めたタイトル。
    let title: String
    /// 選んだ時刻の文字。出さないときは `nil`。
    let time: String?
    /// タイトルの行数の上限。`stacked` のときだけ 1 より大きくなる。
    let titleLines: Int
    /// `minimal` のときの文字の大きさ。
    let fontSize: CGFloat

    /// 幅を測るときの、折り返さない幅。
    static let unlimited: CGFloat = 100_000
    /// 2 行以上のブロックにする高さ。
    static let stackedMinimumHeight: CGFloat = 40
    /// 1 行のブロックで、タイトルと時刻の間に空ける幅。
    static let lineGap: CGFloat = 6
    static let maxTitleLines = 2

    /// 時刻の文字の候補。長い順。`timeText` は「10:00〜10:15」「〜12:00」「23:00〜」の形。
    /// `label` があれば、「未回答」「辞退」を付けたものを先頭の候補にする。
    static func timeCandidates(timeText: String, label: String?, includesLabel: Bool) -> [String] {
        var result: [String] = []
        if includesLabel, let label { result.append("\(timeText)  \(label)") }
        result.append(timeText)
        let parts = timeText.split(separator: "〜", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, !parts[0].isEmpty { result.append(String(parts[0])) }
        return result
    }

    /// - Parameters:
    ///   - width: 文字を置ける幅。
    ///   - height: 文字を置ける高さ。
    static func make(
        title: String, timeText: String, label: String?, width: CGFloat, height: CGFloat, measure: Measure
    ) -> DayBlockTextPlan {
        let width = max(0, width)
        let height = max(0, height)
        let lineHeight = measure("あ", .lineTitle, unlimited).height
        if height >= stackedMinimumHeight {
            let titleLineHeight = measure("あ", .stackedTitle, unlimited).height
            let timeLineHeight = measure("あ", .time, unlimited).height
            let time = timeCandidates(timeText: timeText, label: label, includesLabel: true)
                .first { measure($0, .time, unlimited).width <= width }
            let usable = height - (time == nil ? 0 : timeLineHeight)
            let lines = min(maxTitleLines, max(1, Int((usable / titleLineHeight).rounded(.down))))
            let fitted = fit(title, role: .stackedTitle, width: width, lines: lines, lineHeight: titleLineHeight, measure: measure)
            return DayBlockTextPlan(mode: .stacked, title: fitted, time: time, titleLines: lines, fontSize: 0)
        }
        guard height >= lineHeight else {
            // 1 行に満たない高さ。文字の大きさを高さに合わせて小さくする。
            let size = max(6, (height / 1.25).rounded(.down))
            let role = Role.tinyTitle(fontSize: size)
            let tinyHeight = measure("あ", role, unlimited).height
            let fitted = fit(title, role: role, width: width, lines: 1, lineHeight: tinyHeight, measure: measure)
            return DayBlockTextPlan(mode: .minimal, title: fitted, time: nil, titleLines: 1, fontSize: size)
        }
        let titleWidth = measure(title, .lineTitle, unlimited).width
        for time in timeCandidates(timeText: timeText, label: label, includesLabel: false) {
            if titleWidth + lineGap + measure(time, .time, unlimited).width <= width {
                return DayBlockTextPlan(mode: .singleLine, title: title, time: time, titleLines: 1, fontSize: 0)
            }
        }
        let fitted = fit(title, role: .lineTitle, width: width, lines: 1, lineHeight: lineHeight, measure: measure)
        return DayBlockTextPlan(mode: .singleLine, title: fitted, time: nil, titleLines: 1, fontSize: 0)
    }

    /// `title` を、幅 `width` で `lines` 行に収める。収まらなければ、収まる最長の先頭部分に「…」を付ける。
    static func fit(
        _ title: String, role: Role, width: CGFloat, lines: Int, lineHeight: CGFloat, measure: Measure
    ) -> String {
        let limit = lineHeight * CGFloat(lines) + 0.5
        func fits(_ text: String) -> Bool {
            measure(text, role, width).height <= limit && (lines > 1 || measure(text, role, unlimited).width <= width)
        }
        if fits(title) { return title }
        let characters = Array(title)
        // 先頭から count 文字 + 「…」が収まる最大の count を二分探索する。収まる長さは count について単調である。
        var low = 0
        var high = characters.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(String(characters[..<middle]) + "…") { low = middle } else { high = middle - 1 }
        }
        return String(characters[..<low]) + "…"
    }
}
