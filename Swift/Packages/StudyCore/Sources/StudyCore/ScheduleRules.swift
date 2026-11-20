/// Returns an error message, or nil when [blocks] don't overlap. Gaps are fine.
public func validateSchedule(_ blocks: [Block]) -> String? {
    let s = sortedByStart(blocks)
    for (a, b) in zip(s, s.dropFirst()) where a.end > b.start {
        return "「\(a.name)」(\(rangeLabel(a)))と「\(b.name)」(\(rangeLabel(b)))の時間が重なっています"
    }
    return nil
}

/// "9:00〜10:00".
public func rangeLabel(_ b: Block) -> String {
    "\(LogicalDay.clock(b.start))〜\(LogicalDay.clock(b.end))"
}

/// Result of an edit: the whole new schedule, or an error message.
public typealias EditResult = Result<[Block], ScheduleError>

public struct ScheduleError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

private func rangeError(_ name: String) -> ScheduleError {
    ScheduleError("「\(name)」の時間が1日の区切り（翌朝4:00）を越えています")
}

private func validRange(_ s: Int, _ e: Int) -> Bool {
    s >= 0 && e <= LogicalDay.minutesPerDay && e > s
}

/// Change only the target block's time.
public func applySingleChange(_ blocks: [Block], id: String, newStart: Int, newEnd: Int) -> EditResult {
    guard let target = blocks.first(where: { $0.id == id }) else {
        return .failure(ScheduleError("対象ブロックが見つかりません"))
    }
    guard validRange(newStart, newEnd) else { return .failure(rangeError(target.name)) }
    let updated = blocks.map { $0.id == id ? $0.with(start: newStart, end: newEnd) : $0 }
    if let err = validateSchedule(updated) { return .failure(ScheduleError(err)) }
    return .success(updated)
}

/// Change the target and shift every later block by (new end − old end).
/// Never clamps: overlap or crossing 4:00 is an error.
public func applyCascadeShift(_ blocks: [Block], id: String, newStart: Int, newEnd: Int) -> EditResult {
    guard let target = blocks.first(where: { $0.id == id }) else {
        return .failure(ScheduleError("対象ブロックが見つかりません"))
    }
    guard validRange(newStart, newEnd) else { return .failure(rangeError(target.name)) }
    let shift = newEnd - target.end
    var updated: [Block] = []
    for b in blocks {
        var s = b.start, e = b.end
        if b.id == id {
            s = newStart
            e = newEnd
        } else if b.start >= target.start && shift != 0 {
            s += shift
            e += shift
        }
        guard validRange(s, e) else {
            return .failure(ScheduleError("ずらすと「\(b.name)」が1日の区切り（翌朝4:00）を越えます"))
        }
        updated.append(b.with(start: s, end: e))
    }
    if let err = validateSchedule(updated) { return .failure(ScheduleError(err)) }
    return .success(updated)
}

/// Drag reorder: gaps stay at their slot positions, blocks keep their
/// durations and are laid out in [newOrder]. nil if it would pass 4:00.
public func reorderSchedule(_ blocks: [Block], newOrder: [String]) -> [Block]? {
    let s = sortedByStart(blocks)
    guard let first = s.first else { return [] }
    let gaps = zip(s, s.dropFirst()).map { $1.start - $0.end }
    let byId = Dictionary(s.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var t = first.start
    var out: [Block] = []
    for (i, id) in newOrder.enumerated() {
        guard let b = byId[id] else { return nil }
        let end = t + b.duration
        if end > LogicalDay.minutesPerDay || t < 0 { return nil }
        out.append(b.with(start: t, end: end))
        t = end + (i < gaps.count ? gaps[i] : 0)
    }
    return out
}

/// Fill [start, end) with study/rest repeats. The last block is truncated at
/// [end]. [restMinutes] == 0 means study blocks only.
public func pomodoroFill(start: Int, end: Int, studyMinutes: Int, restMinutes: Int,
                         newId: () -> String) -> [Block] {
    guard studyMinutes > 0, restMinutes >= 0, end > start else { return [] }
    var out: [Block] = []
    var cursor = start, studyN = 0, restN = 0
    var studyTurn = true
    while cursor < end {
        let want = studyTurn ? studyMinutes : restMinutes
        if want <= 0 {
            studyTurn = true
            continue
        }
        let blockEnd = min(cursor + want, end)
        let name: String
        if studyTurn {
            studyN += 1
            name = "勉強\(studyN)"
        } else {
            restN += 1
            name = "休憩\(restN)"
        }
        out.append(Block(id: newId(), name: name, type: studyTurn ? .study : .rest, start: cursor, end: blockEnd))
        cursor = blockEnd
        studyTurn.toggle()
    }
    return out
}
