/// A study⇄rest switch moment.
public struct Chime: Hashable, Sendable {
    public let at: LocalDateTime
    public let next: Block

    public init(at: LocalDateTime, next: Block) {
        self.at = at
        self.next = next
    }

    /// Notification text.
    public var title: String { next.isStudy ? "勉強の時間です" : "休憩の時間です" }
    public var body: String { "\(next.name)（〜\(LogicalDay.clock(next.end))）" }
}

/// Switch moments after [now], over [days] logical days starting today.
///
/// A chime happens only where one block ends exactly when a block of the other
/// type starts: the start/end of free time and the end of the day are silent.
/// [scheduleFor] returns the schedule in effect on a logical date, so weekday
/// presets on future days are taken into account.
public func planChimes(now: LocalDateTime, days: Int, limit: Int = 60,
                       scheduleFor: (CivilDate) -> [Block]) -> [Chime] {
    var out: [Chime] = []
    func add(_ at: LocalDateTime, _ next: Block) {
        if at > now { out.append(Chime(at: at, next: next)) }
    }
    let today = LogicalDay.date(of: now)
    var prevDayLast: Block?
    for i in 0..<max(days, 0) {
        let date = today.adding(days: i)
        let s = sortedByStart(scheduleFor(date))
        // 4:00 boundary between the previous day's last block and today's first.
        if let first = s.first, let prev = prevDayLast,
           prev.end == LogicalDay.minutesPerDay, first.start == 0, prev.type != first.type {
            add(LogicalDay.toDateTime(date, 0), first)
        }
        for (a, b) in zip(s, s.dropFirst()) where a.end == b.start && a.type != b.type {
            add(LogicalDay.toDateTime(date, b.start), b)
        }
        prevDayLast = s.last
        if out.count >= limit { break }
    }
    return Array(out.prefix(limit))
}

/// Stable 31-bit id for a chime's content (FNV-1a over UTF-16 code units).
/// Same formula as the Flutter app, so chimes it registered are recognised.
/// [epochMillis] is the chime's instant (the caller resolves the time zone).
public func chimeId(_ c: Chime, epochMillis: Int64) -> Int {
    let key = "\(epochMillis)|\(c.next.name)|\(c.next.type.rawValue)|\(c.next.end)"
    var h: UInt32 = 0x811c_9dc5
    for unit in key.utf16 {
        h = (h ^ UInt32(unit)) &* 0x0100_0193
    }
    return Int(h & 0x7FFF_FFFF)
}

/// What to cancel and what to add so that [pendingIds] matches [wanted]
/// (id → chime, in plan order).
public struct ChimeDiff<Item> {
    public let cancel: [Int]
    public let add: [(id: Int, item: Item)]
}

public func diffChimes<Item>(pendingIds: Set<Int>, wanted: [(id: Int, item: Item)]) -> ChimeDiff<Item> {
    var seen = Set<Int>()
    var unique: [(id: Int, item: Item)] = []
    for w in wanted where seen.insert(w.id).inserted {
        unique.append(w)
    }
    return ChimeDiff(
        cancel: pendingIds.filter { !seen.contains($0) }.sorted(),
        add: unique.filter { !pendingIds.contains($0.id) }
    )
}
