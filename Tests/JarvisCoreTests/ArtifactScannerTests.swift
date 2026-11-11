import Foundation
import Testing
@testable import JarvisCore

@Suite struct ArtifactScannerTests {
    let ev = ArtifactScanner.events(in: CoreFixture.claude.appendingPathComponent("projects/-work-shop/artifact-session.jsonl"), sessionId: "S")

    @Test func publishOpenAndReadAreFound() {
        #expect(ev.map(\.url.lastPathComponent) == ["A", "A", "B", "C"])
        #expect(ev.map(\.shown) == [true, true, true, false])
        #expect(ev.map(\.description) == ["First description", "Second description", nil, nil])
        #expect(ev.map(\.title) == [nil, "Shop Review", nil, nil])
        #expect(ev.first?.filePath == "/work/shop/review.html")
        #expect(ev.allSatisfy { $0.sessionId == "S" })
        #expect(ev.map(\.url.absoluteString).last == "https://claude.ai/artifact/C")     // a query on the link is dropped
    }

    @Test func theTimeOfTheCallIsKept() {
        #expect(ev.first?.at == ISO8601DateFormatter().date(from: "2026-11-09T10:00:00Z"))
        #expect(ev.last?.at == ISO8601DateFormatter().date(from: "2026-11-09T10:15:00Z"))
    }

    @Test func mentionsFailuresAndOtherActionsAreIgnored() {
        for ignored in ["D", "E", "F", "G", "H", "J"] {
            #expect(!ev.contains { $0.url.lastPathComponent == ignored }, "link \(ignored) should have been ignored")
        }
        #expect(ev.count == 4)
        #expect(ArtifactScanner.events(in: CoreFixture.claude.appendingPathComponent("no-such-file.jsonl"), sessionId: "S").isEmpty)
    }
}

@Suite struct ArtifactIndexTests {
    static let link = "https://claude.ai/artifact/"

    /// A projects folder with history files written by the test.
    final class Bench {
        let root: URL
        let claude: URL
        let cache: URL
        private let lock = NSLock()
        private var scanned: [String] = []

        init() throws {
            root = try tempDir()
            claude = root.appendingPathComponent("claude")
            cache = root.appendingPathComponent("cache/artifact-index.json")
            try FileManager.default.createDirectory(at: claude.appendingPathComponent("projects/-work-shop"), withIntermediateDirectories: true)
        }

        func file(_ session: String) -> URL { claude.appendingPathComponent("projects/-work-shop/\(session).jsonl") }

        func append(_ session: String, id: String, input: [String: Any], result: String, at time: String) throws {
            let use: [String: Any] = ["type": "assistant", "timestamp": time,
                                      "message": ["content": [["type": "tool_use", "id": id, "name": "Artifact", "input": input]]]]
            let answer: [String: Any] = ["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": id, "content": result]]]]
            var text = (try? String(contentsOf: file(session), encoding: .utf8)) ?? ""
            for record in [use, answer] {
                text += String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.withoutEscapingSlashes]), as: UTF8.self) + "\n"
            }
            try text.write(to: file(session), atomically: true, encoding: .utf8)
        }

        /// An index whose scans are counted.
        func index(maxAgeDays: Int = 30) -> ArtifactIndex {
            ArtifactIndex(claudeDir: claude, cacheFile: cache, maxAgeDays: maxAgeDays) { [self] file, session in
                lock.withLock { scanned.append(session) }
                return ArtifactScanner.events(in: file, sessionId: session)
            }
        }

        func takeScanned() -> [String] {
            lock.withLock {
                defer { scanned = [] }
                return scanned.sorted()
            }
        }
    }

    @Test func theIndexMergesSessionsAndCaches() throws {
        let b = try Bench()
        try b.append("one", id: "t1", input: ["file_path": "/work/shop/a.html", "description": "The shop review"], result: "Published \(Self.link)A", at: "2026-11-09T10:00:00.000Z")
        try b.append("two", id: "t1", input: ["action": "read", "url": Self.link + "A"], result: "{}", at: "2026-11-09T11:00:00.000Z")
        try b.append("two", id: "t2", input: ["file_path": "/work/shop/b.html", "title": "Second page"], result: "Published \(Self.link)B", at: "2026-11-09T12:00:00.000Z")

        let cards = b.index().refresh()
        #expect(cards.map(\.url.lastPathComponent) == ["B", "A"])                     // newest first
        let a = try #require(cards.last)
        #expect(a.description == "The shop review")
        #expect(a.links == [ArtifactLink(sessionId: "two", shown: false, at: ISO8601DateFormatter().date(from: "2026-11-09T11:00:00Z")!),
                            ArtifactLink(sessionId: "one", shown: true, at: ISO8601DateFormatter().date(from: "2026-11-09T10:00:00Z")!)])
        #expect(b.takeScanned() == ["one", "two"])

        #expect(b.index().refresh() == cards)                                         // a new index object reads the cache file
        #expect(b.takeScanned() == [])

        try b.append("one", id: "t2", input: ["action": "open", "url": Self.link + "B"], result: "Opened.", at: "2026-11-09T13:00:00.000Z")
        let again = b.index().refresh()
        #expect(b.takeScanned() == ["one"])
        #expect(again.first?.links.map(\.sessionId) == ["one", "two"])
    }

    @Test func aLocalPageTitleFillsAMissingTitle() throws {
        let b = try Bench()
        let page = b.root.appendingPathComponent("review.html")
        try "<!doctype html><html><head><meta charset=\"utf-8\"><TITLE>\n  Shop &amp; Review </TITLE></head><body></body></html>".write(to: page, atomically: true, encoding: .utf8)
        try b.append("one", id: "t1", input: ["file_path": page.path, "description": "x"], result: "Published \(Self.link)A", at: "2026-11-09T10:00:00.000Z")
        try b.append("one", id: "t2", input: ["file_path": b.root.appendingPathComponent("gone.html").path], result: "Published \(Self.link)B", at: "2026-11-09T10:01:00.000Z")
        let cards = b.index().refresh()
        #expect(cards.first { $0.url.lastPathComponent == "A" }?.title == "Shop & Review")
        #expect(cards.first { $0.url.lastPathComponent == "B" }?.title == nil)
    }

    @Test func oldHistoryFilesAreLeftOut() throws {
        let b = try Bench()
        try b.append("old", id: "t1", input: ["file_path": "/x.html"], result: "Published \(Self.link)A", at: "2026-01-01T10:00:00.000Z")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-40 * 86_400)], ofItemAtPath: b.file("old").path)
        #expect(b.index().refresh().isEmpty)
        #expect(b.takeScanned() == [])
        #expect(b.index(maxAgeDays: 60).refresh().count == 1)
    }

    @Test func aDamagedCacheIsRebuilt() throws {
        let b = try Bench()
        try b.append("one", id: "t1", input: ["file_path": "/x.html"], result: "Published \(Self.link)A", at: "2026-11-09T10:00:00.000Z")
        try FileManager.default.createDirectory(at: b.cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: b.cache)
        #expect(b.index().refresh().count == 1)
    }
}
