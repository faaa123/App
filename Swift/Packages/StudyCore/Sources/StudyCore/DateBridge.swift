import Foundation

/// Conversions between `Date` and the core's wall-clock types, using the
/// device calendar (or a fixed one in tests).
extension Instant {
    public init(_ date: Date, calendar: Calendar = .current) {
        self.init(local: LocalDateTime(date, calendar: calendar),
                  epochMillis: Int64((date.timeIntervalSince1970 * 1000).rounded(.down)))
    }
}

extension LocalDateTime {
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1,
                  hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0)
    }

    /// The instant this wall-clock time denotes (nil only if it does not exist).
    public func date(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day,
                                           hour: hour, minute: minute, second: second))
    }
}

extension CivilDate {
    /// Local midnight of this date.
    public func date(calendar: Calendar = .current) -> Date? {
        LocalDateTime(date: self, seconds: 0).date(calendar: calendar)
    }
}

extension StudyController {
    /// When the next logical day begins (the next 4:00).
    public func nextDayStart(calendar: Calendar = .current) -> Date? {
        LogicalDay.toDateTime(today.adding(days: 1), 0).date(calendar: calendar)
    }
}
