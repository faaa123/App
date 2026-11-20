import Foundation
import Observation

/// A moment as both wall-clock time (for the schedule) and an absolute instant
/// (for ordering presets). The app builds it from `Date` and the device's
/// calendar; tests build it directly.
public struct Instant: Sendable, Hashable {
    public let local: LocalDateTime
    public let epochMillis: Int64

    public init(local: LocalDateTime, epochMillis: Int64) {
        self.local = local
        self.epochMillis = epochMillis
    }
}

/// Delivers study⇄rest chimes. Fire-and-forget: implementations apply plans
/// in the background and never block the controller.
@MainActor
public protocol ChimeScheduler: AnyObject {
    /// Replaces every pending chime with [chimes].
    func replaceAll(_ chimes: [Chime])
}

@MainActor
public final class NoopChimeScheduler: ChimeScheduler {
    public init() {}
    public func replaceAll(_ chimes: [Chime]) {}
}

/// State and operations of the study feature. There is a single schedule:
/// edits are permanent. Weekday presets replace it when their day arrives.
@MainActor
@Observable
public final class StudyController {
    private let store: any StudyStore
    private let chimes: any ChimeScheduler
    /// Single source of the current time (swap in tests).
    public let now: () -> Instant
    @ObservationIgnored public var log: (String) -> Void = { print($0) }

    private var data = StudyData()
    /// The logical day the data was last rolled over to.
    public private(set) var currentDay: CivilDate?

    static let keepSummaryDays = 120
    static let backfillDays = 90
    static let chimeDays = 7

    public init(store: any StudyStore, chimes: any ChimeScheduler, now: @escaping () -> Instant) {
        self.store = store
        self.chimes = chimes
        self.now = now
    }

    public var blocks: [Block] { data.blocks }
    public var presets: [Preset] { data.presets }
    public var threshold: Int { data.threshold }
    public var today: CivilDate { LogicalDay.date(of: now().local) }

    public func newId() -> String { UUID().uuidString.lowercased() }

    /// Loads the data and rolls over to today.
    public func load() {
        if let json = store.load() {
            let (parsed, lossy) = StudyData.parse(json)
            data = parsed
            // Keep the original before any save drops what could not be parsed.
            if lossy { store.keepCopy(tag: "partial") }
        }
        let day = today
        currentDay = day
        if rollOver(to: day) { save() }
        replanChimes()
    }

    /// Call on resume and at 4:00. Finalizes past days, applies today's weekday
    /// preset when the logical day changed, and re-plans chimes. Returns
    /// whether the logical day changed.
    @discardableResult
    public func refresh(force: Bool = false) -> Bool {
        let day = today
        guard force || day != currentDay else {
            // Same day: still re-plan, so chimes dropped while notifications
            // were off are registered again (the scheduler skips a plan that
            // is still registered).
            replanChimes()
            return false
        }
        currentDay = day
        let changed = rollOver(to: day)
        replanChimes()
        if changed { save() }
        return true
    }

    // MARK: - schedule

    /// Replace the schedule (already validated by the caller).
    public func setBlocks(_ blocks: [Block]) {
        data.blocks = sortedByStart(blocks)
        commit()
    }

    /// Adds [block]; returns an error message or nil.
    @discardableResult
    public func addBlock(_ block: Block) -> String? { tryApply(data.blocks + [block]) }

    @discardableResult
    public func addBlocks(_ added: [Block]) -> String? { tryApply(data.blocks + added) }

    public func deleteBlock(id: String) { setBlocks(data.blocks.filter { $0.id != id }) }

    public func deleteAll() { setBlocks([]) }

    /// Returns an error message or nil.
    @discardableResult
    public func reorder(_ newOrder: [String]) -> String? {
        guard let r = reorderSchedule(data.blocks, newOrder: newOrder) else {
            return "並び替えると1日の区切り（翌朝4:00）を越えます"
        }
        setBlocks(r)
        return nil
    }

    private func tryApply(_ next: [Block]) -> String? {
        if let err = validateSchedule(next) { return err }
        setBlocks(next)
        return nil
    }

    // MARK: - presets

    public func saveAsPreset(name: String) {
        data.presets.append(Preset(id: newId(), name: name, blocks: data.blocks, updatedAt: now().epochMillis))
        // A new preset has no weekdays, so the chime plan is unchanged.
        save()
    }

    public func applyPreset(id: String) {
        guard let p = data.presets.first(where: { $0.id == id }) else { return }
        setBlocks(freshIds(p.blocks))
    }

    public func deletePreset(id: String) {
        data.presets.removeAll { $0.id == id }
        commit()
    }

    public func setPresetWeekdays(id: String, _ weekdays: Set<Int>) {
        guard let i = data.presets.firstIndex(where: { $0.id == id }) else { return }
        // "The preset linked later wins" (D-2): only adding a weekday counts as
        // linking, so removing one does not take over other shared weekdays.
        let added = !weekdays.subtracting(data.presets[i].weekdays).isEmpty
        data.presets[i].weekdays = weekdays
        if added { data.presets[i].updatedAt = now().epochMillis }
        commit()
    }

    public func presetForWeekday(_ weekday: Int) -> Preset? {
        var best: Preset?
        for p in data.presets where !p.blocks.isEmpty && p.weekdays.contains(weekday) {
            if best == nil || p.updatedAt > best!.updatedAt { best = p }
        }
        return best
    }

    // MARK: - undo

    /// What the user edits directly: the schedule and the presets. Restoring a
    /// snapshot never touches history (summaries) or the rollover state.
    public struct Snapshot: Equatable, Sendable {
        public let blocks: [Block]
        public let presets: [Preset]
    }

    public var snapshot: Snapshot { Snapshot(blocks: data.blocks, presets: data.presets) }

    public func restore(_ s: Snapshot) {
        data.blocks = s.blocks
        data.presets = s.presets
        commit()
    }

    /// Weekdays (0 = Sunday …) that more than one preset claims, with the
    /// preset that wins there.
    public func contestedWeekdays() -> [(weekday: Int, winner: Preset)] {
        (0..<7).compactMap { w in
            let claimants = data.presets.filter { !$0.blocks.isEmpty && $0.weekdays.contains(w) }
            guard claimants.count > 1, let winner = presetForWeekday(w) else { return nil }
            return (w, winner)
        }
    }

    // MARK: - stats

    public func setThreshold(_ minutes: Int) {
        data.threshold = max(10, minutes)
        save()
    }

    /// Planned study minutes per logical date, including today (live).
    public func minutesByDate() -> [String: Int] {
        var m = data.summaries
        m[today.key] = totalStudyMinutes(data.blocks)
        return m
    }

    public func streak() -> Int {
        calculateStreak(today: today, minutesByDate: minutesByDate(), threshold: data.threshold)
    }

    // MARK: - internals

    private func freshIds(_ blocks: [Block]) -> [Block] { blocks.map { $0.with(id: newId()) } }

    /// Schedule in effect on [date] (today or later), simulating weekday presets.
    public func scheduleFor(_ date: CivilDate) -> [Block] {
        var sched = data.blocks
        var d = today.adding(days: 1)
        while d <= date {
            if let p = presetForWeekday(d.weekday) { sched = p.blocks }
            d = d.adding(days: 1)
        }
        return sched
    }

    /// Finalizes days before [day] and, once per logical day, applies [day]'s
    /// weekday preset. Returns whether anything changed.
    private func rollOver(to day: CivilDate) -> Bool {
        let yesterday = day.adding(days: -1)
        let last = data.lastRecorded.flatMap(CivilDate.init(key:))
        var advanced = false
        var changed = false
        if let last {
            if last < yesterday {
                // Finalize the missing days. The stored schedule is the one in
                // effect on the last-used day (its preset was applied when that
                // day began, then possibly edited), so presets are only
                // replayed for later days.
                let lastUsed = last.adding(days: 1)
                var sched = data.blocks
                var replaced = false
                var d = lastUsed
                let floor = yesterday.adding(days: -Self.backfillDays)
                while d <= yesterday {
                    if d > lastUsed, let p = presetForWeekday(d.weekday) {
                        sched = p.blocks
                        replaced = true
                    }
                    if d > floor { data.summaries[d.key] = totalStudyMinutes(sched) }
                    d = d.adding(days: 1)
                }
                if replaced { data.blocks = freshIds(sched) }
                data.lastRecorded = yesterday.key
                advanced = true
            } else if last > yesterday {
                // The clock went back (it was ahead, or a time-zone move):
                // forget summaries of days that have not finished yet, so
                // rollover resumes tomorrow. No preset apply: today may already
                // have been edited.
                let todayKey = day.key
                data.summaries = data.summaries.filter { $0.key < todayKey }
                data.lastRecorded = yesterday.key
                changed = true
            }
        } else {
            // First run: no history to invent.
            data.lastRecorded = yesterday.key
            advanced = true
        }
        if advanced {
            // Today's weekday preset, only when the day begins (D-12): same-day
            // edits and manual applies survive restarts.
            if let p = presetForWeekday(day.weekday), !sameSchedule(p.blocks, data.blocks) {
                data.blocks = freshIds(p.blocks)
            }
        }
        let cutoff = day.adding(days: -Self.keepSummaryDays).key
        let before = data.summaries.count
        data.summaries = data.summaries.filter { $0.key >= cutoff }
        return advanced || changed || data.summaries.count != before
    }

    /// The in-memory data is already updated (views refresh), then persist.
    private func commit() {
        replanChimes()
        save()
    }

    private func save() {
        do {
            try store.save(data.toJSON())
        } catch {
            log("study save failed: \(error)")
        }
    }

    /// The chimes for the next days, from now.
    public func plannedChimes() -> [Chime] {
        planChimes(now: now().local, days: Self.chimeDays, scheduleFor: scheduleFor)
    }

    private func replanChimes() {
        chimes.replaceAll(plannedChimes())
    }
}
