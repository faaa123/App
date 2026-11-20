import Testing
@testable import StudyCore

// Port of test/study/core_test.dart.

@Suite struct CivilDateTests {
    @Test func rollsOverAndCountsWeekdays() {
        #expect(day(2026, 1, 0) == day(2025, 12, 31))
        #expect(day(2026, 13, 1) == day(2027, 1, 1))
        #expect(day(2024, 2, 28).adding(days: 1) == day(2024, 2, 29))
        #expect(day(2026, 11, 20).weekday == 5) // Friday
        #expect(day(2026, 11, 22).weekday == 0) // Sunday
        #expect(day(1969, 12, 31).adding(days: 1) == day(1970, 1, 1))
        #expect(CivilDate(daysSinceEpoch: day(1900, 3, 1).daysSinceEpoch) == day(1900, 3, 1))
    }

    @Test func keys() {
        #expect(day(2026, 3, 5).key == "2026-03-05")
        #expect(CivilDate(key: "2026-03-05") == day(2026, 3, 5))
        #expect(CivilDate(key: "2026-3-5") == nil)
        #expect(CivilDate(key: "abcd-ef-gh") == nil)
        #expect(CivilDate(key: "") == nil)
    }
}

@Suite struct LogicalDayTests {
    @Test func originAndLastMinute() {
        #expect(o(4, 0) == 0)
        #expect(o(3, 59) == 1439)
        #expect(o(23, 0) == 1140)
        #expect(o(1, 0) == 1260)
    }

    @Test func endAtFourIsEndOfDay() {
        #expect(LogicalDay.toEndOffset(4, 0) == 1440)
    }

    @Test func earlyHoursBelongToPreviousDay() {
        #expect(LogicalDay.date(of: dt(2026, 11, 21, 3, 59)) == day(2026, 11, 20))
        #expect(LogicalDay.date(of: dt(2026, 11, 21, 4)) == day(2026, 11, 21))
    }

    @Test func clockLabel() {
        #expect(LogicalDay.clock(o(9, 5)) == "9:05")
        #expect(LogicalDay.clock(1440) == "4:00")
    }

    @Test func toDateTimeCrossesMidnight() {
        #expect(LogicalDay.toDateTime(day(2026, 1, 1), o(1, 0)) == dt(2026, 1, 2, 1, 0))
        #expect(LogicalDay.toDateTime(day(2026, 1, 1), 1440) == dt(2026, 1, 2, 4, 0))
    }
}

@Suite struct BlockTests {
    @Test func rejectsCrossingFourAndZeroLength() {
        #expect(Block.validated(id: "x", name: "x", type: .study, start: 100, end: 100) == nil)
        #expect(Block.validated(id: "x", name: "x", type: .study, start: 1430, end: 1450) == nil)
        #expect(Block.validated(id: "x", name: "x", type: .study, start: 1430, end: 1440) != nil)
    }
}

@Suite struct ResolveNowTests {
    let blocks = [
        study("s1", o(9, 0), o(11, 0)),
        rest("r1", o(11, 0), o(11, 30)),
        study("late", o(23, 0), o(1, 0)),
    ]

    @Test func insideABlock() throws {
        let s = try #require(resolveNow(blocks, now: dt(2026, 1, 1, 10, 0, 30)).inBlock)
        #expect(s.block.id == "s1")
        #expect(s.remainingSeconds == 59 * 60 + 30)
        #expect(s.next?.id == "r1")
    }

    @Test func boundaryStartsNextBlock() throws {
        let s = try #require(resolveNow(blocks, now: dt(2026, 1, 1, 11, 0)).inBlock)
        #expect(s.block.id == "r1")
    }

    @Test func freeTimeShowsNext() {
        guard case .free(let next, let secs) = resolveNow(blocks, now: dt(2026, 1, 1, 12, 0)) else {
            Issue.record("expected free"); return
        }
        #expect(next.id == "late")
        #expect(secs == 11 * 3600)
    }

    @Test func blockCrossingMidnight() throws {
        let s = try #require(resolveNow(blocks, now: dt(2026, 1, 2, 0, 30)).inBlock)
        #expect(s.block.id == "late")
        #expect(s.remainingSeconds == 30 * 60)
    }

    @Test func dayEndedUntilTomorrowFirst() {
        #expect(resolveNow(blocks, now: dt(2026, 1, 2, 2, 0)) == .dayEnded(secondsUntilTomorrowFirst: 7 * 3600))
    }

    @Test func dayEndedUsesTomorrowsSchedule() {
        let t = [study("t", o(6, 0), o(7, 0))]
        #expect(resolveNow(blocks, now: dt(2026, 1, 2, 2, 0), tomorrow: t)
            == .dayEnded(secondsUntilTomorrowFirst: 4 * 3600))
        #expect(resolveNow([], now: dt(2026, 1, 1, 12), tomorrow: t)
            == .dayEnded(secondsUntilTomorrowFirst: 18 * 3600))
        #expect(resolveNow(blocks, now: dt(2026, 1, 2, 2, 0), tomorrow: [])
            == .dayEnded(secondsUntilTomorrowFirst: nil))
    }

    @Test func noSchedule() {
        #expect(resolveNow([], now: dt(2026, 1, 1, 12)) == .dayEnded(secondsUntilTomorrowFirst: nil))
    }
}

@Suite struct EditTests {
    let blocks = [
        study("a", o(9, 0), o(10, 0)),
        rest("b", o(10, 0), o(10, 15)),
        study("c", o(10, 30), o(11, 30)),
    ]

    @Test func overlapRejectedGapsAllowed() {
        #expect(validateSchedule(blocks) == nil)
        #expect(validateSchedule(blocks + [study("d", o(9, 30), o(9, 45))]) != nil)
    }

    @Test func singleChangeOnlyMovesTarget() {
        let r = applySingleChange(blocks, id: "b", newStart: o(10, 0), newEnd: o(10, 20))
        #expect(r.isOk)
        #expect(r.blocks?.first { $0.id == "c" }?.start == o(10, 30))
    }

    @Test func singleChangeThatOverlapsFails() {
        #expect(!applySingleChange(blocks, id: "b", newStart: o(10, 0), newEnd: o(10, 45)).isOk)
    }

    @Test func cascadeShiftsLaterBlocks() throws {
        let r = try #require(applyCascadeShift(blocks, id: "a", newStart: o(9, 0), newEnd: o(10, 30)).blocks)
        let m = Dictionary(uniqueKeysWithValues: r.map { ($0.id, $0) })
        #expect(m["b"]?.start == o(10, 30))
        #expect(m["c"]?.start == o(11, 0))
    }

    @Test func cascadePastFourFails() {
        let late = [study("x", o(2, 0), o(3, 0)), rest("y", o(3, 0), o(3, 50))]
        #expect(!applyCascadeShift(late, id: "x", newStart: o(2, 0), newEnd: o(3, 30)).isOk)
    }

    @Test func missingTarget() {
        #expect(applySingleChange(blocks, id: "zz", newStart: 0, newEnd: 10).error == "対象ブロックが見つかりません")
    }
}

@Suite struct MessageTests {
    @Test func overlapNamesBothBlocks() {
        #expect(validateSchedule([study("勉強", o(9, 0), o(10, 0)), study("勉強", o(9, 30), o(11, 0))])
            == "「勉強」(9:00〜10:00)と「勉強」(9:30〜11:00)の時間が重なっています")
    }

    @Test func dayEndWithoutInternalTerm() throws {
        let r = applySingleChange([study("a", o(9, 0), o(10, 0))], id: "a",
                                  newStart: o(9, 0), newEnd: LogicalDay.minutesPerDay + 1)
        let err = try #require(r.error)
        #expect(!err.contains("論理日"))
        #expect(err.contains("1日の区切り（翌朝4:00）"))
    }
}

@Suite struct ReorderTests {
    @Test func keepsGapsInSlots() throws {
        let blocks = [study("a", 0, 60), rest("b", 70, 80), study("c", 80, 110)]
        let r = try #require(reorderSchedule(blocks, newOrder: ["c", "a", "b"]))
        let m = Dictionary(uniqueKeysWithValues: r.map { ($0.id, ($0.start, $0.end)) })
        #expect(m["c"]! == (0, 30))
        #expect(m["a"]! == (40, 100))
        #expect(m["b"]! == (100, 110))
    }

    @Test func nilInsteadOfPassingFour() {
        // Only reachable with overlapping input (a negative gap).
        let blocks = [study("a", 0, 10), study("b", 100, 1440), rest("c", 200, 300)]
        #expect(reorderSchedule(blocks, newOrder: ["b", "c", "a"]) == nil)
    }
}

@Suite struct PomodoroTests {
    @Test func alternatesAndTruncates() {
        var n = 0
        let r = pomodoroFill(start: 0, end: 70, studyMinutes: 25, restMinutes: 5) {
            defer { n += 1 }
            return "\(n)"
        }
        let got = r.map { "\($0.name) \($0.start) \($0.end)" }
        #expect(got == ["勉強1 0 25", "休憩1 25 30", "勉強2 30 55", "休憩2 55 60", "勉強3 60 70"])
    }

    @Test func restZeroMeansStudyOnly() {
        let r = pomodoroFill(start: 0, end: 50, studyMinutes: 25, restMinutes: 0) { "x" }
        #expect(r.count == 2)
        #expect(r.allSatisfy { $0.isStudy })
    }
}

@Suite struct StatsTests {
    let blocks = [study("a", 0, 60), rest("b", 60, 70), study("c", 70, 100)]

    @Test func totalAndElapsed() {
        #expect(totalStudyMinutes(blocks) == 90)
        #expect(elapsedStudyMinutes(blocks, offset: 80) == 70)
        #expect(elapsedStudyMinutes(blocks, offset: 0) == 0)
    }

    @Test func streak() {
        let today = day(2026, 1, 10)
        func k(_ d: Int) -> String { today.adding(days: -d).key }
        #expect(calculateStreak(today: today, minutesByDate: [k(0): 0, k(1): 30, k(2): 40, k(4): 60], threshold: 30) == 2)
        #expect(calculateStreak(today: today, minutesByDate: [k(0): 30, k(1): 30], threshold: 30) == 2)
    }
}

@Suite struct ChimePlanTests {
    @Test func onlyOnSwitches() {
        let blocks = [
            study("a", o(9, 0), o(10, 0)),
            rest("b", o(10, 0), o(10, 10)),
            study("c", o(10, 10), o(11, 0)),
            study("d", o(11, 0), o(12, 0)), // same type: silent
            rest("e", o(13, 0), o(13, 10)), // after a gap: silent
        ]
        let chimes = planChimes(now: dt(2026, 1, 1, 8, 0), days: 1) { _ in blocks }
        #expect(chimes.map(\.next.id) == ["b", "c"])
        #expect(chimes.first?.at == dt(2026, 1, 1, 10, 0))
    }

    @Test func skipsPastAndSpansDays() {
        let blocks = [study("a", o(9, 0), o(10, 0)), rest("b", o(10, 0), o(10, 10))]
        let chimes = planChimes(now: dt(2026, 1, 1, 11, 0), days: 3) { _ in blocks }
        #expect(chimes.map(\.at) == [dt(2026, 1, 2, 10, 0), dt(2026, 1, 3, 10, 0)])
    }

    @Test func atFourOnlyWhenTypeChanges() {
        func plan(_ nextType: BlockType) -> [Chime] {
            planChimes(now: dt(2026, 1, 1, 8, 0), days: 2) { d in
                d.day == 1 ? [rest("late", o(3, 0), LogicalDay.minutesPerDay)] : [blk("early", nextType, 0, 60)]
            }
        }
        let switched = plan(.study)
        #expect(switched.map(\.at) == [dt(2026, 1, 2, 4, 0)])
        #expect(switched.first?.next.id == "early")
        #expect(plan(.rest).isEmpty)
    }

    @Test func limit() {
        var blocks: [Block] = []
        for i in 0..<20 { blocks.append(blk("\(i)", i % 2 == 0 ? .study : .rest, i * 10, i * 10 + 10)) }
        #expect(planChimes(now: dt(2026, 1, 1, 0, 0), days: 7) { _ in blocks }.count == 60)
    }

    @Test func notificationText() {
        let c = Chime(at: dt(2026, 1, 1, 10), next: rest("休憩", o(10, 0), o(10, 10)))
        #expect(c.title == "休憩の時間です")
        #expect(c.body == "休憩（〜10:10）")
    }
}

// Port of test/study/chime_diff_test.dart.
@Suite struct ChimeDiffTests {
    func chime(_ hour: Int, _ name: String) -> (id: Int, item: Chime) {
        let c = Chime(at: dt(2026, 11, 20, hour), next: Block(id: name, name: name, type: .rest, start: 0, end: 10))
        return (chimeId(c, epochMillis: Int64(hour) * 3_600_000), c)
    }

    @Test func idsAreStableAndContentBased() {
        let a = chime(10, "a"), b = chime(11, "b")
        #expect(a.id == chime(10, "a").id)
        #expect(a.id != b.id)
        #expect(a.id >= 0)
    }

    @Test func matchesFlutterFormula() {
        // FNV-1a of "0|a|rest|10" masked to 31 bits, as computed by the Dart code.
        let c = Chime(at: dt(1970, 1, 1), next: Block(id: "a", name: "a", type: .rest, start: 0, end: 10))
        var h: UInt32 = 0x811c_9dc5
        for u in "0|a|rest|10".utf16 { h = (h ^ UInt32(u)) &* 0x0100_0193 }
        #expect(chimeId(c, epochMillis: 0) == Int(h & 0x7FFF_FFFF))
    }

    @Test func resumeOnlyAddsTail() {
        let b = chime(11, "b"), c = chime(12, "c")
        let d = diffChimes(pendingIds: [b.id], wanted: [b, c])
        #expect(d.cancel.isEmpty)
        #expect(d.add.map(\.item) == [c.item])
    }

    @Test func unchangedPlanTouchesNothing() {
        let a = chime(10, "a"), b = chime(11, "b")
        let d = diffChimes(pendingIds: [a.id, b.id], wanted: [a, b])
        #expect(d.cancel.isEmpty)
        #expect(d.add.isEmpty)
    }

    @Test func staleCancelledDroppedReadded() {
        let a = chime(10, "a"), b = chime(11, "b")
        let d = diffChimes(pendingIds: [0, 1, a.id], wanted: [a, b])
        #expect(Set(d.cancel) == [0, 1])
        #expect(d.add.map(\.item) == [b.item])
    }
}
