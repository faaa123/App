import Testing
@testable import StudyCore

@Suite struct FormatTests {
    @Test func countdown() {
        #expect(Format.countdown(5400) == "1:30:00")
        #expect(Format.countdown(300) == "5:00")
        #expect(Format.countdown(65) == "1:05")
        #expect(Format.countdown(3605) == "1:00:05")
        #expect(Format.countdown(-3) == "0:00")
    }

    @Test func minutesAndUntil() {
        #expect(Format.minutes(95) == "1時間35分")
        #expect(Format.minutes(30) == "30分")
        #expect(Format.minutes(120) == "2時間")
        #expect(Format.until(61) == "2分")
        #expect(Format.until(60) == "1分")
    }

    @Test func dates() {
        #expect(Format.date(day(2026, 11, 20)) == "11月20日（金）")
        #expect(Format.shortDate(day(2026, 1, 5)) == "1/5")
    }

    @Test func names() {
        #expect(Format.titled(study("勉強2", 0, 10)) == "勉強2")
        #expect(Format.titled(study("英語", 0, 10)) == "勉強　英語")
        #expect(Format.nameWithType(rest("散歩", 0, 10)) == "散歩（休憩）")
        #expect(Format.nameWithType(rest("休憩1", 0, 10)) == "休憩1")
    }
}
