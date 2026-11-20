/// What the main screen shows for "now".
public enum NowStatus: Equatable, Sendable {
    case inBlock(InBlock)
    case free(next: Block, secondsUntilNext: Int)
    /// `secondsUntilTomorrowFirst` is nil when there is no schedule at all.
    case dayEnded(secondsUntilTomorrowFirst: Int?)

    public struct InBlock: Equatable, Sendable {
        public let block: Block
        public let remainingSeconds: Int
        public let progress: Double
        public let next: Block?
        public let secondsUntilNext: Int?
    }
}

/// Resolve the status at [now] for today's [blocks]. Block membership is
/// decided by the minute (like the Android app); countdowns use seconds.
/// [tomorrow] is the next logical day's schedule (weekday presets may differ);
/// it defaults to [blocks].
public func resolveNow(_ blocks: [Block], now: LocalDateTime, tomorrow: [Block]? = nil) -> NowStatus {
    let offset = LogicalDay.offset(of: now)
    let nowSec = offset * 60 + now.second
    let s = sortedByStart(blocks)
    if let current = s.first(where: { $0.contains(offset) }) {
        let next = s.first { $0.start >= current.end }
        let elapsed = nowSec - current.start * 60
        let progress = min(max(Double(elapsed) / Double(current.duration * 60), 0), 1)
        return .inBlock(.init(
            block: current,
            remainingSeconds: current.end * 60 - nowSec,
            progress: progress,
            next: next,
            secondsUntilNext: next.map { $0.start * 60 - nowSec }
        ))
    }
    if let next = s.first(where: { $0.start > offset }) {
        return .free(next: next, secondsUntilNext: next.start * 60 - nowSec)
    }
    let first = sortedByStart(tomorrow ?? blocks).first
    return .dayEnded(secondsUntilTomorrowFirst: first.map {
        LogicalDay.minutesPerDay * 60 - nowSec + $0.start * 60
    })
}
