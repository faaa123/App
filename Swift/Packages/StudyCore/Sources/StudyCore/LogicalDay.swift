/// Logical day helpers. A logical day starts at 4:00; 0:00–3:59 belongs to the
/// previous day. Times are mapped to minute offsets in [0, 1440) from 4:00, so a
/// block like 23:00–01:00 needs no special handling.
public enum LogicalDay {
    public static let originMinutes = 4 * 60
    public static let minutesPerDay = 24 * 60

    /// Clock time → offset in [0, 1440).
    public static func toOffset(_ hour: Int, _ minute: Int) -> Int {
        CivilDate.floorMod(hour * 60 + minute - originMinutes, minutesPerDay)
    }

    /// Clock time used as a block *end* → offset in (0, 1440]. 4:00 means the
    /// end of the logical day (1440), never 0.
    public static func toEndOffset(_ hour: Int, _ minute: Int) -> Int {
        let o = toOffset(hour, minute)
        return o == 0 ? minutesPerDay : o
    }

    public static func offset(of t: LocalDateTime) -> Int { toOffset(t.hour, t.minute) }

    /// The logical date that [t] belongs to.
    public static func date(of t: LocalDateTime) -> CivilDate {
        t.hour < 4 ? t.date.adding(days: -1) : t.date
    }

    /// Offset on [logicalDate] → wall-clock time.
    public static func toDateTime(_ logicalDate: CivilDate, _ offset: Int) -> LocalDateTime {
        LocalDateTime(date: logicalDate, seconds: (originMinutes + offset) * 60)
    }

    /// Offset → "H:MM" clock label.
    public static func clock(_ offset: Int) -> String {
        let (h, m) = clockParts(offset)
        return "\(h):\(m < 10 ? "0" : "")\(m)"
    }

    /// Offset → (hour, minute) on the clock.
    public static func clockParts(_ offset: Int) -> (hour: Int, minute: Int) {
        let m = CivilDate.floorMod(offset + originMinutes, minutesPerDay)
        return (m / 60, m % 60)
    }
}
