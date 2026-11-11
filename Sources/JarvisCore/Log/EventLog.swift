import Foundation

/// One request, as written to the local log used for measuring and tuning. No audio is ever stored.
public struct EventRecord: Codable, Equatable {
    public var at: Date
    public var heard: String
    /// One of: opened, offered, nothing, back, unheard, gone, left, failed.
    public var outcome: String
    public var title: String?
    public var ms: [String: Int]
    public var step: String?
    public var top: [String: Double]?
    /// How loud the recording was, in ten-thousandths of full scale: average, loudest (0.3 s) and peak.
    public var sound: [String: Int]?
    /// What the speech model wrote, when that was not usable as a request.
    public var raw: String?
    /// Everything Jev answered, by question and then by title (see `PickTrace.answers`).
    public var jev: [String: [String: Double]]?

    public init(at: Date, heard: String, outcome: String, title: String?, ms: [String: Int], step: String?, top: [String: Double]?,
                sound: [String: Int]? = nil, raw: String? = nil, jev: [String: [String: Double]]? = nil) {
        self.sound = sound
        self.raw = raw
        self.jev = jev
        self.at = at
        self.heard = heard
        self.outcome = outcome
        self.title = title
        self.ms = ms
        self.step = step
        self.top = top
    }
}

/// Appends records to a file, one JSON object per line.
public final class EventLog: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder

    public init(file: URL) {
        self.file = file
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    public func write(_ record: EventRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard var line = try? encoder.encode(record) else { return }
        line.append(0x0A)
        let manager = FileManager.default
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: file.path) {
            manager.createFile(atPath: file.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
