import BarlunariDomain

extension Weekday {
    /// 設定画面の選択肢に出す名前。例は `月曜日`。
    public var displayName: String {
        switch self {
        case .sunday: "日曜日"
        case .monday: "月曜日"
        case .tuesday: "火曜日"
        case .wednesday: "水曜日"
        case .thursday: "木曜日"
        case .friday: "金曜日"
        case .saturday: "土曜日"
        }
    }
}
