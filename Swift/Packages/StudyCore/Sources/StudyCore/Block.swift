public enum BlockType: String, Sendable, Hashable, CaseIterable {
    case study, rest
}

/// One schedule block. Offsets are logical-day minutes; the interval is the
/// half-open [start, end). A block never crosses the 4:00 boundary.
public struct Block: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let type: BlockType
    public let start: Int
    public let end: Int

    /// Traps on an invalid range (a programming error); use [validated] for
    /// untrusted input.
    public init(id: String, name: String, type: BlockType, start: Int, end: Int) {
        precondition(Self.isValidRange(start: start, end: end), "invalid block range: start=\(start) end=\(end)")
        self.id = id
        self.name = name
        self.type = type
        self.start = start
        self.end = end
    }

    /// nil when [start, end) is empty or leaves the logical day.
    public static func validated(id: String, name: String, type: BlockType, start: Int, end: Int) -> Block? {
        isValidRange(start: start, end: end) ? Block(id: id, name: name, type: type, start: start, end: end) : nil
    }

    public static func isValidRange(start: Int, end: Int) -> Bool {
        start >= 0 && start < LogicalDay.minutesPerDay && end > start && end <= LogicalDay.minutesPerDay
    }

    public var duration: Int { end - start }
    public func contains(_ offset: Int) -> Bool { offset >= start && offset < end }
    public var isStudy: Bool { type == .study }

    public func with(id: String? = nil, name: String? = nil, type: BlockType? = nil,
                     start: Int? = nil, end: Int? = nil) -> Block {
        Block(id: id ?? self.id, name: name ?? self.name, type: type ?? self.type,
              start: start ?? self.start, end: end ?? self.end)
    }

    /// Same content, ignoring id.
    public func sameContent(as o: Block) -> Bool {
        name == o.name && type == o.type && start == o.start && end == o.end
    }
}

public func sortedByStart(_ blocks: some Sequence<Block>) -> [Block] {
    // Stable: equal starts (only in overlapping input) keep their order.
    blocks.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
}

/// Same blocks (ignoring ids and order).
public func sameSchedule(_ a: [Block], _ b: [Block]) -> Bool {
    guard a.count == b.count else { return false }
    return zip(sortedByStart(a), sortedByStart(b)).allSatisfy { $0.sameContent(as: $1) }
}
