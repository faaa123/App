import Foundation
import Testing
@testable import StudyCore

@Suite struct DateBridgeTests {
    var tokyo: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    @Test func roundTrip() throws {
        let d = Date(timeIntervalSince1970: 1_763_604_000) // 2025-11-20 11:00 JST
        let i = Instant(d, calendar: tokyo)
        #expect(i.local == dt(2025, 11, 20, 11, 0, 0))
        #expect(i.epochMillis == 1_763_604_000_000)
        #expect(try #require(i.local.date(calendar: tokyo)) == d)
    }

    @Test func nextFourOClock() throws {
        let t = dt(2026, 11, 21, 2, 30) // logical 11/20
        let next = try #require(LogicalDay.toDateTime(LogicalDay.date(of: t).adding(days: 1), 0).date(calendar: tokyo))
        #expect(LocalDateTime(next, calendar: tokyo) == dt(2026, 11, 21, 4, 0))
    }
}
