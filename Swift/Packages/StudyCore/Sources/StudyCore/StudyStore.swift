import Foundation

/// Loads and saves the study feature's JSON document.
@MainActor
public protocol StudyStore: AnyObject {
    /// nil when there is nothing stored or it cannot be read.
    func load() -> JSONValue?
    func save(_ json: JSONValue) throws
    /// Keeps a copy of the stored file as it is now (before a save would drop
    /// entries that could not be parsed).
    func keepCopy(tag: String)
}

/// One JSON file (`study.json`), written atomically (temp file + rename), in
/// the same place and format as the Flutter app.
@MainActor
public final class FileStudyStore: StudyStore {
    public let directory: URL
    public var log: (String) -> Void = { print($0) }
    private let now: () -> Date

    public init(directory: URL, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    /// `Library/Application Support`, where Flutter's path_provider kept it.
    public static func applicationSupport() throws -> FileStudyStore {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        return FileStudyStore(directory: dir)
    }

    public var fileURL: URL { directory.appendingPathComponent("study.json") }

    private var stamp: String { String(Int64(now().timeIntervalSince1970 * 1000)) }

    /// An unreadable file is kept aside as `study.json.corrupt-<epochMs>`.
    public func load() -> JSONValue? {
        let f = fileURL
        guard FileManager.default.fileExists(atPath: f.path) else { return nil }
        do {
            let json = try JSONValue.parse(try Data(contentsOf: f))
            guard case .object = json else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return json
        } catch {
            log("study.json unreadable, starting fresh: \(error)")
            try? FileManager.default.moveItem(at: f, to: directory.appendingPathComponent("study.json.corrupt-\(stamp)"))
            return nil
        }
    }

    public func save(_ json: JSONValue) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try json.encoded().write(to: fileURL, options: .atomic)
    }

    /// Copies study.json to `study.json.<tag>-<epochMs>` and keeps only the
    /// newest few copies per tag.
    public func keepCopy(tag: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        do {
            try fm.copyItem(at: fileURL, to: directory.appendingPathComponent("study.json.\(tag)-\(stamp)"))
            let prefix = "study.json.\(tag)-"
            let copies = try fm.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix(prefix) }
                .sorted(by: >)
            for old in copies.dropFirst(Self.keepCopies) {
                try? fm.removeItem(at: directory.appendingPathComponent(old))
            }
        } catch {
            log("study backup failed: \(error)")
        }
    }

    static let keepCopies = 3
}

/// In-memory store for tests and previews.
@MainActor
public final class MemoryStudyStore: StudyStore {
    public var data: JSONValue?
    /// Tags passed to keepCopy.
    public private(set) var copies: [String] = []

    public init(_ data: JSONValue? = nil) { self.data = data }

    public func load() -> JSONValue? { data }
    public func save(_ json: JSONValue) throws { data = json }
    public func keepCopy(tag: String) { copies.append(tag) }
}
