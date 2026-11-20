/// A named schedule, optionally auto-applied on some weekdays.
public struct Preset: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let blocks: [Block]
    /// 0 = Sunday … 6 = Saturday. Empty = never auto-applied.
    public var weekdays: Set<Int>
    /// Epoch milliseconds. Newer wins when several presets claim a weekday.
    public var updatedAt: Int64

    public init(id: String, name: String, blocks: [Block], weekdays: Set<Int> = [], updatedAt: Int64) {
        self.id = id
        self.name = name
        self.blocks = blocks
        self.weekdays = weekdays
        self.updatedAt = updatedAt
    }
}

/// Everything the study feature persists, in the Flutter app's `study.json`
/// format (version 1), so data carries over unchanged.
public struct StudyData: Equatable, Sendable {
    public var blocks: [Block] = []
    public var presets: [Preset] = []
    /// Logical date key → planned study minutes of that finished day.
    public var summaries: [String: Int] = [:]
    /// Last finished logical day already written to [summaries].
    public var lastRecorded: String?
    /// Streak threshold in minutes.
    public var threshold = 30

    public init(blocks: [Block] = [], presets: [Preset] = [], summaries: [String: Int] = [:],
                lastRecorded: String? = nil, threshold: Int = 30) {
        self.blocks = blocks
        self.presets = presets
        self.summaries = summaries
        self.lastRecorded = lastRecorded
        self.threshold = threshold
    }

    // MARK: - JSON

    public func toJSON() -> JSONValue {
        .object([
            "version": .int(1),
            "blocks": .array(blocks.map(Self.blockJSON)),
            "presets": .array(presets.map { p in
                .object([
                    "id": .string(p.id),
                    "name": .string(p.name),
                    "blocks": .array(p.blocks.map(Self.blockJSON)),
                    "weekdays": .array(p.weekdays.sorted().map { .int($0) }),
                    "updatedAt": .int(Int(p.updatedAt)),
                ])
            }),
            "summaries": .object(summaries.mapValues { .int($0) }),
            "lastRecorded": lastRecorded.map { .string($0) } ?? .null,
            "threshold": .int(threshold),
        ])
    }

    private static func blockJSON(_ b: Block) -> JSONValue {
        .object([
            "id": .string(b.id),
            "name": .string(b.name),
            "type": .string(b.type.rawValue),
            "start": .int(b.start),
            "end": .int(b.end),
        ])
    }

    /// Parses what can be parsed. Entries that fail (bad types, impossible
    /// offsets, overlaps with an earlier block) are dropped instead of failing
    /// the whole file; `lossy` tells whether anything stored could not be kept
    /// (so the next save would lose it).
    public static func parse(_ j: JSONValue) -> (data: StudyData, lossy: Bool) {
        var lossy = j["version"] != .int(1)
        let rawPresets = j["presets"]?.arrayValue ?? []
        let presets = rawPresets.compactMap { parsePreset($0, onDrop: { lossy = true }) }
        let rawSummaries = j["summaries"]?.objectValue ?? [:]
        var summaries: [String: Int] = [:]
        for (k, v) in rawSummaries {
            if validDateKey(k) != nil, let n = v.intValue, n >= 0 { summaries[k] = n }
        }
        let t = j["threshold"]
        // setThreshold keeps it ≥ 10; calculateStreak traps on ≤ 0.
        let validThreshold = t?.intValue.map { $0 >= 10 && $0 <= 1440 } ?? false
        let rawLast = j["lastRecorded"]
        let lastRecorded = rawLast?.stringValue.flatMap(validDateKey)
        let blocks = parseBlocks(j["blocks"], onDrop: { lossy = true })
        let data = StudyData(
            blocks: blocks,
            presets: presets,
            summaries: summaries,
            lastRecorded: lastRecorded,
            threshold: validThreshold ? t!.intValue! : 30
        )
        lossy = lossy
            || presets.count != rawPresets.count
            || summaries.count != rawSummaries.count
            || (t != nil && t != .null && !validThreshold)
            || (rawLast != nil && rawLast != .null && lastRecorded == nil)
        return (data, lossy)
    }

    static func parseBlocks(_ list: JSONValue?, onDrop: () -> Void) -> [Block] {
        var out: [Block] = []
        for item in list?.arrayValue ?? [] {
            if let id = item["id"]?.stringValue,
               let name = item["name"]?.stringValue,
               let type = item["type"]?.stringValue.flatMap(BlockType.init(rawValue:)),
               let start = item["start"]?.intValue,
               let end = item["end"]?.intValue,
               let block = Block.validated(id: id, name: name, type: type, start: start, end: end),
               out.allSatisfy({ block.end <= $0.start || block.start >= $0.end }) {
                out.append(block)
            } else {
                onDrop()
            }
        }
        return sortedByStart(out)
    }

    static func parsePreset(_ j: JSONValue, onDrop: () -> Void) -> Preset? {
        let rawWeekdays: [JSONValue]
        switch j["weekdays"] {
        case nil, .null?: rawWeekdays = []
        case .array(let a)?: rawWeekdays = a
        default: return nil
        }
        var valid = Set<Int>()
        for w in rawWeekdays {
            if let n = w.intValue, (0...6).contains(n) { valid.insert(n) }
        }
        var dropped = false
        let blocks = parseBlocks(j["blocks"], onDrop: {
            dropped = true
            onDrop()
        })
        guard let id = j["id"]?.stringValue,
              let name = j["name"]?.stringValue,
              let updatedAt = j["updatedAt"]?.intValue
        else { return nil }
        if valid.count != rawWeekdays.count { onDrop() }
        // A preset that lost blocks must never auto-apply: it would silently
        // replace (or empty) that day's schedule. It can still be applied by hand.
        return Preset(id: id, name: name, blocks: blocks,
                      weekdays: dropped || blocks.isEmpty ? [] : valid,
                      updatedAt: Int64(updatedAt))
    }
}

/// "yyyy-MM-dd" or nil.
func validDateKey(_ s: String) -> String? {
    let u = Array(s.utf8)
    guard u.count == 10, u[4] == UInt8(ascii: "-"), u[7] == UInt8(ascii: "-") else { return nil }
    for (i, c) in u.enumerated() where i != 4 && i != 7 {
        guard c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") else { return nil }
    }
    return s
}
