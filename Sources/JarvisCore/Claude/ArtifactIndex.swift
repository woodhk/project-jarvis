import Foundation

/// Every artifact that recent sessions published, opened or read, built from their history files.
/// Scanning is slow the first time (the files are large), so results are cached per file and a file is read again
/// only when its size or modification time changes.
public final class ArtifactIndex: @unchecked Sendable {
    public typealias Scan = @Sendable (_ historyFile: URL, _ sessionId: String) -> [ArtifactEvent]

    private struct Entry: Codable {
        var size: Int64
        var modified: Double
        var events: [ArtifactEvent]
    }

    private let claudeDir: URL
    private let cacheFile: URL
    private let maxAge: TimeInterval
    private let scan: Scan
    private let lock = NSLock()
    private var entries: [String: Entry]?

    public init(claudeDir: URL, cacheFile: URL, maxAgeDays: Int = 30,
                scan: @escaping Scan = { ArtifactScanner.events(in: $0, sessionId: $1) }) {
        self.claudeDir = claudeDir
        self.cacheFile = cacheFile
        self.maxAge = TimeInterval(maxAgeDays) * 86_400
        self.scan = scan
    }

    /// The artifact cards, newest first.
    public func refresh() -> [ArtifactCard] {
        lock.lock()
        defer { lock.unlock() }
        var known = entries ?? ((try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: cacheFile))) ?? [:])
        var current: [String: Entry] = [:]
        var changed = false
        let manager = FileManager.default
        let projects = claudeDir.appendingPathComponent("projects")
        let oldest = Date().addingTimeInterval(-maxAge)
        for folder in (try? manager.contentsOfDirectory(atPath: projects.path)) ?? [] {
            let folderURL = projects.appendingPathComponent(folder)
            for name in (try? manager.contentsOfDirectory(atPath: folderURL.path)) ?? [] where name.hasSuffix(".jsonl") {
                let file = folderURL.appendingPathComponent(name)
                guard let attributes = try? manager.attributesOfItem(atPath: file.path),
                      let modified = attributes[.modificationDate] as? Date, modified >= oldest else { continue }
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                if let cached = known[file.path], cached.size == size, cached.modified == modified.timeIntervalSince1970 {
                    current[file.path] = cached
                } else {
                    let events = scan(file, String(name.dropLast(6))).map(Self.withPageTitle)
                    current[file.path] = Entry(size: size, modified: modified.timeIntervalSince1970, events: events)
                    changed = true
                }
            }
        }
        if changed || current.count != known.count {
            try? manager.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(current).write(to: cacheFile, options: .atomic)
        }
        known = current
        entries = known
        return Self.cards(from: known.values.flatMap(\.events))
    }

    /// A publish without a title takes the `<title>` of the page that was published, when that file still exists.
    private static func withPageTitle(_ event: ArtifactEvent) -> ArtifactEvent {
        guard event.title == nil, let path = event.filePath, let title = pageTitle(ofFileAt: path) else { return event }
        var titled = event
        titled.title = title
        return titled
    }

    static func pageTitle(ofFileAt path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 65_536)) ?? Data(), as: UTF8.self)
        guard let expression = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = expression.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
              let range = Range(match.range(at: 1), in: head) else { return nil }
        var title = String(head[range])
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            title = title.replacingOccurrences(of: entity, with: character)
        }
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : title
    }

    /// One card per link. Its title and description are the latest ones given; each session has one link,
    /// dated by the last time it showed the page (or, if it never did, the last time it read it).
    static func cards(from events: [ArtifactEvent]) -> [ArtifactCard] {
        let byLink = Dictionary(grouping: events.sorted { $0.at < $1.at }, by: \.url)
        let cards = byLink.map { url, events -> ArtifactCard in
            let links = Dictionary(grouping: events, by: \.sessionId).map { session, events -> ArtifactLink in
                let shown = events.filter(\.shown)
                let last = (shown.isEmpty ? events : shown).map(\.at).max() ?? Date(timeIntervalSince1970: 0)
                return ArtifactLink(sessionId: session, shown: !shown.isEmpty, at: last)
            }.sorted { ($0.at, $1.sessionId) > ($1.at, $0.sessionId) }
            return ArtifactCard(url: url, title: events.last { $0.title != nil }?.title,
                                description: events.last { $0.description != nil }?.description, links: links)
        }
        return cards.sorted {
            let (a, b) = ($0.links.first?.at ?? .distantPast, $1.links.first?.at ?? .distantPast)
            return a != b ? a > b : $0.url.absoluteString < $1.url.absoluteString
        }
    }
}
