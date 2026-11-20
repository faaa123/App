/// Japanese labels shared by the screens.
public enum Format {
    /// 5400 → "1:30:00", 300 → "5:00".
    public static func countdown(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        let h = s / 3600, m = s % 3600 / 60, sec = s % 60
        let ss = sec < 10 ? "0\(sec)" : "\(sec)"
        if h > 0 { return "\(h):\(m < 10 ? "0" : "")\(m):\(ss)" }
        return "\(m):\(ss)"
    }

    /// 95 → "1時間35分", 30 → "30分".
    public static func minutes(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)分" }
        return m == 0 ? "\(h)時間" : "\(h)時間\(m)分"
    }

    /// Rounded-up minutes for "あと○分" style labels.
    public static func until(_ seconds: Int) -> String { minutes((seconds + 59) / 60) }

    public static let weekdayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    /// "11月20日（金）".
    public static func date(_ d: CivilDate) -> String {
        "\(d.month)月\(d.day)日（\(weekdayLabels[d.weekday])）"
    }

    /// "11/20".
    public static func shortDate(_ d: CivilDate) -> String { "\(d.month)/\(d.day)" }

    /// Block name with its type, without repeating a name that already starts
    /// with the type label ("勉強2" stays "勉強2").
    public static func titled(_ b: Block, separator: String = "　") -> String {
        let label = typeLabel(b.type)
        return b.name.hasPrefix(label) ? b.name : "\(label)\(separator)\(b.name)"
    }

    /// "英語（勉強）", or just "勉強2".
    public static func nameWithType(_ b: Block) -> String {
        let label = typeLabel(b.type)
        return b.name.hasPrefix(label) ? b.name : "\(b.name)（\(label)）"
    }

    public static func typeLabel(_ t: BlockType) -> String { t == .study ? "勉強" : "休憩" }
}
