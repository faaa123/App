/// Planned study minutes for the whole day.
public func totalStudyMinutes(_ blocks: [Block]) -> Int {
    blocks.lazy.filter(\.isStudy).reduce(0) { $0 + $1.duration }
}

/// Study minutes elapsed by [offset]: finished blocks fully, the running one
/// partially, future ones not at all.
public func elapsedStudyMinutes(_ blocks: [Block], offset: Int) -> Int {
    blocks.lazy.filter(\.isStudy).reduce(0) { sum, b in
        if offset >= b.end { return sum + b.duration }
        if offset > b.start { return sum + offset - b.start }
        return sum
    }
}

/// Consecutive achieved days ending today. Today not yet achieved does not
/// break the streak (the day isn't over). Missing days count as not achieved.
/// [threshold] must be > 0.
public func calculateStreak(today: CivilDate, minutesByDate: [String: Int], threshold: Int) -> Int {
    precondition(threshold > 0, "threshold must be > 0")
    var streak = (minutesByDate[today.key] ?? 0) >= threshold ? 1 : 0
    var d = today.adding(days: -1)
    while (minutesByDate[d.key] ?? 0) >= threshold {
        streak += 1
        d = d.adding(days: -1)
    }
    return streak
}
