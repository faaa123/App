/// A calendar date without time or time zone (proleptic Gregorian).
/// Arithmetic is pure integer math, so results never depend on the device.
public struct CivilDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Out-of-range month/day values roll over (like Dart's `DateTime`), so
    /// `CivilDate(year: 2026, month: 1, day: 0)` is 2025-12-31.
    public init(year: Int, month: Int, day: Int) {
        let m0 = month - 1
        let y = year + Self.floorDiv(m0, 12)
        let m = Self.floorMod(m0, 12) + 1
        self.init(daysSinceEpoch: Self.daysFromCivil(y, m, 1) + day - 1)
    }

    /// Days since 1970-01-01.
    public init(daysSinceEpoch z: Int) {
        let z = z + 719_468
        let era = Self.floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        month = m
        day = d
    }

    public var daysSinceEpoch: Int { Self.daysFromCivil(year, month, day) }

    public func adding(days: Int) -> CivilDate {
        CivilDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// 0 = Sunday … 6 = Saturday (same as the Android app).
    public var weekday: Int { Self.floorMod(daysSinceEpoch + 4, 7) }  // 1970-01-01 was a Thursday.

    /// "yyyy-MM-dd".
    public var key: String {
        "\(Self.pad(year, 4))-\(Self.pad(month, 2))-\(Self.pad(day, 2))"
    }

    /// Parses a "yyyy-MM-dd" key; nil when malformed.
    public init?(key: String) {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0 >= "0" && $0 <= "9" } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var description: String { key }

    public static func < (a: CivilDate, b: CivilDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // MARK: - helpers

    private static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = floorDiv(y, 400)
        let yoe = y - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    static func floorMod(_ a: Int, _ b: Int) -> Int { a - floorDiv(a, b) * b }

    private static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }
}

/// A wall-clock moment: a civil date and the second within that day.
public struct LocalDateTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let date: CivilDate
    /// [0, 86400).
    public let secondOfDay: Int

    /// Out-of-range components roll over into neighbouring days.
    public init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) {
        self.init(date: CivilDate(year: year, month: month, day: day),
                  seconds: hour * 3600 + minute * 60 + second)
    }

    /// [date] at [seconds] after its midnight (may be negative or ≥ a day).
    public init(date: CivilDate, seconds: Int) {
        self.date = date.adding(days: CivilDate.floorDiv(seconds, 86_400))
        secondOfDay = CivilDate.floorMod(seconds, 86_400)
    }

    public var hour: Int { secondOfDay / 3600 }
    public var minute: Int { secondOfDay / 60 % 60 }
    public var second: Int { secondOfDay % 60 }

    public static func < (a: LocalDateTime, b: LocalDateTime) -> Bool {
        (a.date, a.secondOfDay) < (b.date, b.secondOfDay)
    }

    public var description: String {
        "\(date.key) \(hour):\(minute < 10 ? "0" : "")\(minute):\(second < 10 ? "0" : "")\(second)"
    }
}
