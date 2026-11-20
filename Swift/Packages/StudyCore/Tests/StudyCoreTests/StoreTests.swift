import Foundation
import Testing
@testable import StudyCore

/// A file exactly as the Flutter app writes it (`jsonEncode(StudyData.toJson())`).
let flutterFile = #"""
{"version":1,"blocks":[{"id":"mhx1a2b3c","name":"数学","type":"study","start":300,"end":390},{"id":"mhx1a2b3d","name":"休憩","type":"rest","start":390,"end":405}],"presets":[{"id":"p1","name":"平日","blocks":[{"id":"b1","name":"英語","type":"study","start":1140,"end":1260}],"weekdays":[1,2,3,4,5],"updatedAt":1763600000000}],"summaries":{"2026-11-18":120,"2026-11-19":90},"lastRecorded":"2026-11-19","threshold":40}
"""#

@MainActor
@Suite struct StoreTests {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("studycore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func files(_ dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    @Test func readsFlutterFileWithoutLoss() throws {
        let (data, lossy) = StudyData.parse(try JSONValue.parse(Data(flutterFile.utf8)))
        #expect(!lossy)
        #expect(data.blocks.map(\.name) == ["数学", "休憩"])
        #expect(data.blocks[0].start == 300 && data.blocks[0].end == 390)
        #expect(data.presets.count == 1)
        #expect(data.presets[0].weekdays == [1, 2, 3, 4, 5])
        #expect(data.presets[0].updatedAt == 1_763_600_000_000)
        #expect(data.summaries == ["2026-11-18": 120, "2026-11-19": 90])
        #expect(data.lastRecorded == "2026-11-19")
        #expect(data.threshold == 40)
    }

    @Test func writesTheSameFormat() throws {
        let original = try JSONValue.parse(Data(flutterFile.utf8))
        let (data, _) = StudyData.parse(original)
        #expect(data.toJSON() == original)
        // And round-trips through bytes.
        #expect(try JSONValue.parse(data.toJSON().encoded()) == original)
    }

    @Test func nullLastRecordedIsNotLossy() throws {
        let j = try JSONValue.parse(Data(#"{"version":1,"blocks":[],"presets":[],"summaries":{},"lastRecorded":null,"threshold":30}"#.utf8))
        let (data, lossy) = StudyData.parse(j)
        #expect(!lossy)
        #expect(data.lastRecorded == nil)
        #expect(data.toJSON() == j)
    }

    @Test func jsonKeepsTypesApart() throws {
        let j = try JSONValue.parse(Data(#"{"a":true,"b":1,"c":1.5,"d":"x","e":null}"#.utf8))
        #expect(j["a"] == .bool(true))
        #expect(j["b"] == .int(1))
        #expect(j["c"] == .double(1.5))
        #expect(j["d"] == .string("x"))
        #expect(j["e"] == .null)
    }

    @Test func fileRoundTrip() throws {
        let dir = try tempDir()
        let store = FileStudyStore(directory: dir)
        #expect(store.load() == nil)
        let data = StudyData(blocks: [study("a", 0, 60)], lastRecorded: "2026-11-19")
        try store.save(data.toJSON())
        try store.save(data.toJSON())
        #expect(try files(dir) == ["study.json"]) // no temp file left
        #expect(store.load() == data.toJSON())
    }

    @Test func corruptFileIsKeptAside() throws {
        let dir = try tempDir()
        try Data("{not json".utf8).write(to: dir.appendingPathComponent("study.json"))
        let store = FileStudyStore(directory: dir, now: { Date(timeIntervalSince1970: 1) })
        store.log = { _ in }
        #expect(store.load() == nil)
        #expect(try files(dir) == ["study.json.corrupt-1000"])
    }

    @Test func nonObjectIsKeptAside() throws {
        let dir = try tempDir()
        try Data("[1,2]".utf8).write(to: dir.appendingPathComponent("study.json"))
        let store = FileStudyStore(directory: dir, now: { Date(timeIntervalSince1970: 2) })
        store.log = { _ in }
        #expect(store.load() == nil)
        #expect(try files(dir) == ["study.json.corrupt-2000"])
    }

    @Test func keepCopyKeepsNewestThree() throws {
        let dir = try tempDir()
        var t = 1000.0
        let store = FileStudyStore(directory: dir, now: { Date(timeIntervalSince1970: t) })
        try store.save(StudyData().toJSON())
        for _ in 0..<5 {
            store.keepCopy(tag: "partial")
            t += 1
        }
        #expect(try files(dir) == [
            "study.json",
            "study.json.partial-1002000",
            "study.json.partial-1003000",
            "study.json.partial-1004000",
        ])
    }
}
