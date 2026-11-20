import Foundation
import Testing
@testable import StudyCore

// Port of test/study/controller_test.dart. (The two tests about waiting for
// the notification permission do not apply: ChimeScheduler is fire-and-forget.)

@MainActor
final class RecordingChimes: ChimeScheduler {
    var last: [Chime] = []
    var calls = 0
    func replaceAll(_ chimes: [Chime]) {
        calls += 1
        last = chimes
    }
}

/// Treats wall-clock time as UTC for the absolute instant.
func instant(_ t: LocalDateTime) -> Instant {
    Instant(local: t, epochMillis: Int64(t.date.daysSinceEpoch * 86_400 + t.secondOfDay) * 1000)
}

@MainActor
final class Env {
    var clock = dt(2026, 11, 20, 8) // Friday
    var store = MemoryStudyStore()
    let chimes = RecordingChimes()

    func make() -> StudyController {
        let c = StudyController(store: store, chimes: chimes) { [unowned self] in instant(self.clock) }
        c.log = { _ in }
        c.load()
        return c
    }

    func advance(minutes: Int) {
        clock = LocalDateTime(date: clock.date, seconds: clock.secondOfDay + minutes * 60)
    }
}

@MainActor
func blk(_ c: StudyController, _ name: String, _ t: BlockType, _ s: Int, _ e: Int) -> Block {
    Block(id: c.newId(), name: name, type: t, start: s, end: e)
}

@MainActor
@Suite struct ControllerTests {
    @Test func editsPersistAndReplanChimes() {
        let env = Env()
        let c = env.make()
        #expect(c.addBlock(blk(c, "勉強", .study, o(9, 0), o(10, 0))) == nil)
        #expect(c.addBlock(blk(c, "休憩", .rest, o(10, 0), o(10, 10))) == nil)
        #expect(env.chimes.last.first?.at == dt(2026, 11, 20, 10))
        #expect(c.addBlock(blk(c, "重複", .study, o(9, 30), o(9, 40))) != nil)

        let reopened = env.make()
        #expect(reopened.blocks.map(\.name) == ["勉強", "休憩"])
    }

    @Test func resumeOnSameDayReplans() {
        let env = Env()
        let c = env.make()
        c.addBlock(blk(c, "勉強", .study, o(9, 0), o(10, 0)))
        c.addBlock(blk(c, "休憩", .rest, o(10, 0), o(10, 10)))
        let before = env.chimes.calls
        env.clock = dt(2026, 11, 20, 8, 30)
        #expect(c.refresh() == false)
        #expect(env.chimes.calls == before + 1)
        #expect(env.chimes.last.first?.at == dt(2026, 11, 20, 10))
    }

    @Test func firstRunDoesNotInventHistory() {
        let env = Env()
        let c = env.make()
        c.addBlock(blk(c, "a", .study, o(9, 0), o(10, 0)))
        #expect(c.minutesByDate().count == 1)

        env.clock = dt(2026, 11, 23, 9)
        #expect(c.refresh() == true)
        let m = c.minutesByDate()
        #expect(m["2026-11-20"] == 60)
        #expect(m["2026-11-21"] == 60)
        #expect(m["2026-11-22"] == 60)
        #expect(c.streak() == 4)
    }

    @Test func weekdayPresetAppliesAndIsPlanned() {
        let env = Env()
        let c = env.make()
        c.addBlock(blk(c, "normal", .study, o(9, 0), o(10, 0)))
        c.saveAsPreset(name: "normal")
        c.setBlocks([blk(c, "sat", .study, o(13, 0), o(14, 0)), blk(c, "satRest", .rest, o(14, 0), o(14, 30))])
        c.saveAsPreset(name: "weekend")
        let weekend = c.presets.first { $0.name == "weekend" }!
        c.setPresetWeekdays(id: weekend.id, [6])
        c.applyPreset(id: c.presets.first { $0.name == "normal" }!.id)

        #expect(env.chimes.last.map(\.at).contains(dt(2026, 11, 21, 14)))

        env.clock = dt(2026, 11, 21, 4, 1)
        c.refresh()
        #expect(c.blocks.map(\.name) == ["sat", "satRest"])
    }

    @Test func unlinkingDoesNotTakeOverSharedWeekdays() {
        let env = Env()
        let c = env.make()
        c.addBlock(blk(c, "x", .study, o(9, 0), o(10, 0)))
        c.saveAsPreset(name: "A")
        c.saveAsPreset(name: "B")
        let a = c.presets.first { $0.name == "A" }!.id
        let b = c.presets.first { $0.name == "B" }!.id
        c.setPresetWeekdays(id: a, [1, 2])
        env.advance(minutes: 1)
        c.setPresetWeekdays(id: b, [2])
        #expect(c.presetForWeekday(2)?.name == "B")

        env.advance(minutes: 1)
        c.setPresetWeekdays(id: a, [2])
        #expect(c.presetForWeekday(2)?.name == "B")

        env.advance(minutes: 1)
        c.setPresetWeekdays(id: a, [2, 3])
        #expect(c.presetForWeekday(2)?.name == "A")
    }

    func withSaturdayPreset(_ env: Env) -> StudyController {
        let c = env.make()
        c.setBlocks([blk(c, "sat", .study, o(13, 0), o(14, 0))])
        c.saveAsPreset(name: "weekend")
        c.setPresetWeekdays(id: c.presets[0].id, [6])
        c.setBlocks([blk(c, "fri", .study, o(9, 0), o(10, 0))])
        return c
    }

    @Test func resumingAfterDaysReplaysPresets() {
        let env = Env()
        env.clock = dt(2026, 11, 19, 8) // Thursday
        let c = env.make()
        c.setBlocks([blk(c, "sat", .study, o(13, 0), o(14, 0))])
        c.saveAsPreset(name: "weekend")
        c.setPresetWeekdays(id: c.presets[0].id, [6])
        c.setBlocks([blk(c, "normal", .study, o(9, 0), o(10, 30))])

        env.clock = dt(2026, 11, 23, 8) // Monday
        c.refresh()
        let m = c.minutesByDate()
        #expect(m["2026-11-19"] == 90)
        #expect(m["2026-11-20"] == 90)
        #expect(m["2026-11-21"] == 60)
        #expect(m["2026-11-22"] == 60)
        #expect(c.blocks.map(\.name) == ["sat"])
    }

    @Test func editsOnPresetDayCarryOver() {
        let env = Env()
        let c = withSaturdayPreset(env)
        env.clock = dt(2026, 11, 21, 8)
        c.refresh()
        #expect(c.blocks.map(\.name) == ["sat"])
        c.setBlocks([blk(c, "satEdited", .study, o(13, 0), o(15, 0))])

        env.clock = dt(2026, 11, 22, 8)
        c.refresh()
        #expect(c.minutesByDate()["2026-11-21"] == 120)
        #expect(c.blocks.map(\.name) == ["satEdited"])
    }

    @Test func sameDayEditsSurviveRestart() {
        let env = Env()
        let c = withSaturdayPreset(env)
        env.clock = dt(2026, 11, 21, 8)
        c.refresh()
        c.setBlocks([blk(c, "satEdited", .study, o(13, 0), o(15, 0))])

        env.clock = dt(2026, 11, 21, 12)
        let reopened = env.make()
        #expect(reopened.blocks.map(\.name) == ["satEdited"])
    }

    @Test func clockThatWentBack() {
        let env = Env()
        let c = env.make()
        c.addBlock(blk(c, "a", .study, o(9, 0), o(10, 0)))
        env.clock = dt(2026, 11, 30, 8)
        c.refresh()
        #expect(c.minutesByDate()["2026-11-25"] == 60)

        env.clock = dt(2026, 11, 20, 12)
        c.refresh(force: true)
        #expect(c.minutesByDate().keys.filter { $0 > "2026-11-20" }.isEmpty)

        c.setBlocks([blk(c, "sat", .study, o(13, 0), o(14, 0))])
        c.saveAsPreset(name: "weekend")
        c.setPresetWeekdays(id: c.presets[0].id, [6])
        c.setBlocks([blk(c, "fri", .study, o(9, 0), o(10, 0))])

        env.clock = dt(2026, 11, 21, 8)
        c.refresh()
        #expect(c.blocks.map(\.name) == ["sat"])
        #expect(c.minutesByDate()["2026-11-20"] == 60)
        #expect(c.minutesByDate().keys.filter { $0 > "2026-11-21" }.isEmpty)
    }

    @Test func malformedDataDoesNotBlockLoad() throws {
        let env = Env()
        env.store = MemoryStudyStore(try JSONValue.parse(Data(#"""
        {
          "blocks": [
            {"id": "x", "name": "a", "type": "study", "start": 10, "end": 5},
            {"id": "y", "name": "b", "type": "nap", "start": 10, "end": 20},
            {"id": "z", "name": "ok", "type": "study", "start": 30, "end": 60},
            {"id": "w", "name": "overlap", "type": "rest", "start": 40, "end": 70},
            "garbage"
          ],
          "presets": [
            {"id": "p", "name": 3},
            {"id": "q", "name": "good",
             "blocks": [{"id": "a", "name": "a", "type": "rest", "start": 0, "end": 9999}],
             "weekdays": [1, 9], "updatedAt": 0}
          ],
          "summaries": {"2026-11-01": "many", "2026-11-02": 45, "x": 5},
          "lastRecorded": 12,
          "threshold": "x"
        }
        """#.utf8)))
        let c = env.make()
        #expect(c.blocks.map(\.name) == ["ok"])
        #expect(c.presets.map(\.name) == ["good"])
        #expect(c.presets[0].blocks.isEmpty)
        #expect(c.presets[0].weekdays.isEmpty)
        #expect(c.threshold == 30)
        #expect(c.minutesByDate()["x"] == nil)
        #expect(env.store.copies == ["partial"])

        env.clock = dt(2026, 11, 23, 9)
        c.refresh()
        #expect(c.blocks.map(\.name) == ["ok"])
    }

    @Test func cleanFileIsNotCopiedAside() {
        let env = Env()
        let c = env.make()
        c.addBlock(blk(c, "a", .study, o(9, 0), o(10, 0)))
        c.saveAsPreset(name: "p")
        c.setPresetWeekdays(id: c.presets[0].id, [1])

        _ = env.make()
        #expect(env.store.copies.isEmpty)
    }

    @Test func newerVersionIsCopiedAside() {
        let env = Env()
        env.store = MemoryStudyStore(.object(["version": .int(2), "blocks": .array([])]))
        _ = env.make()
        #expect(env.store.copies == ["partial"])
    }

    @Test(arguments: [0, -5])
    func invalidThresholdFallsBack(t: Int) {
        let env = Env()
        env.store = MemoryStudyStore(.object([
            "threshold": .int(t),
            "summaries": .object(["x": .int(10), "2026-11-19": .int(-3), "2026-11-18": .int(40)]),
        ]))
        let c = env.make()
        #expect(c.threshold == 30)
        _ = c.streak()
        #expect(c.minutesByDate()["x"] == nil)
        #expect(c.minutesByDate()["2026-11-19"] == nil)
        #expect(c.minutesByDate()["2026-11-18"] == 40)
    }

    @Test func thresholdHasAFloor() {
        let env = Env()
        let c = env.make()
        c.setThreshold(5)
        #expect(c.threshold == 10)
    }
}

@MainActor
@Suite struct UndoSnapshotTests {
    @Test func restoreBringsBackBlocksAndPresetsOnly() {
        let env = Env()
        let c = env.make()
        c.addBlock(blk(c, "a", .study, o(9, 0), o(10, 0)))
        c.saveAsPreset(name: "p")
        let before = c.snapshot
        let minutes = c.minutesByDate()
        c.deleteAll()
        c.deletePreset(id: c.presets[0].id)
        #expect(c.blocks.isEmpty && c.presets.isEmpty)
        let calls = env.chimes.calls
        c.restore(before)
        #expect(c.snapshot == before)
        #expect(c.minutesByDate() == minutes)
        #expect(env.chimes.calls == calls + 1) // re-planned
        // Persisted.
        #expect(env.make().blocks.map(\.name) == ["a"])
    }

    @Test func contestedWeekdaysNameTheWinner() {
        let env = Env()
        let c = env.make()
        c.addBlock(blk(c, "x", .study, o(9, 0), o(10, 0)))
        c.saveAsPreset(name: "A")
        c.saveAsPreset(name: "B")
        c.setPresetWeekdays(id: c.presets[0].id, [1, 2])
        env.advance(minutes: 1)
        c.setPresetWeekdays(id: c.presets[1].id, [2, 3])
        let contested = c.contestedWeekdays()
        #expect(contested.map(\.weekday) == [2])
        #expect(contested.first?.winner.name == "B")
    }
}
