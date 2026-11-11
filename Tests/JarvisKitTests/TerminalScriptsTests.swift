import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

extension Fixture {
    static let coreDir = dir.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("JarvisCoreTests/Fixtures")

    /// The acceptance cards shared with the JarvisCore tests.
    static func cards() throws -> CardSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CardSnapshot.self, from: Data(contentsOf: coreDir.appendingPathComponent("acceptance-cards.json")))
    }
}

/// A fixed process table for the session fixtures: 101 and 106 under Terminal, 102 under VS Code.
struct TableInspector: ProcessInspecting {
    let parents: [Int32: Int32] = [101: 100, 100: 80, 102: 110, 110: 112, 106: 130, 130: 80]
    let ttys: [Int32: String] = [101: "/dev/ttys012", 102: "/dev/ttys013", 106: "/dev/ttys015"]
    let paths: [Int32: String] = [80: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
                                  112: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"]
    func isAlive(_ pid: Int32) -> Bool { parents[pid] != nil || paths[pid] != nil }
    func parent(of pid: Int32) -> Int32? { parents[pid] }
    func tty(of pid: Int32) -> String? { ttys[pid] }
    func executablePath(of pid: Int32) -> String? { paths[pid] }
}

@Suite struct TerminalScriptsTests {
    let cards: CardSnapshot
    var discovery: SessionCard { cards.sessions.first { $0.id == "s-discovery" }! }
    static let terminal: @Sendable () -> (bundleId: String, path: String)? = { ("com.apple.Terminal", "/System/Applications/Utilities/Terminal.app") }

    init() throws { cards = try Fixture.cards() }

    @Test func onlyRealTerminalDevicesAreAccepted() throws {
        #expect(try TerminalScripts.focusTab(tty: "/dev/ttys012").contains("\"/dev/ttys012\""))
        #expect(throws: OpenError.self) { try TerminalScripts.focusTab(tty: "/dev/ttys012\" then do shell script \"x") }
        #expect(throws: OpenError.self) { try TerminalScripts.focusTab(tty: "") }
    }

    @Test func theScriptsAreValidAppleScript() throws {
        #expect(try compiles(TerminalScripts.focusTab(tty: "/dev/ttys012")))
        #expect(try compiles(TerminalScripts.frontTTY))
    }

    @Test func aTabThatHasGoneIsReported() async {
        let opener = TerminalOpener(runner: FakeRunner(result: "gone"))
        await #expect(throws: OpenError.gone) { _ = try await opener.open(.terminalTab(tty: "/dev/ttys012")) }
    }

    @Test func aFoundTabOpensWithoutANote() async throws {
        #expect(try await TerminalOpener(runner: FakeRunner(result: "ok")).open(.terminalTab(tty: "/dev/ttys012")) == nil)
        await #expect(throws: OpenError.self) { _ = try await TerminalOpener(runner: FakeRunner(result: "ok")).open(.app(path: "/A.app")) }
    }

    @Test func theFrontTerminalTabBecomesTheFrontSession() async {
        let f = FrontReader(runner: FakeRunner(result: discovery.tty), frontApp: Self.terminal)
        let state = await f.read(cards: cards)
        #expect(state.card == .session(id: "s-discovery"))
        #expect(state.destination == .terminalTab(tty: discovery.tty))
    }

    @Test func aTerminalTabWithoutASessionIsStillAPlaceToGoBackTo() async {
        let f = FrontReader(runner: FakeRunner(result: "/dev/ttys099"), frontApp: Self.terminal)
        #expect(await f.read(cards: cards) == FrontState(card: .none, destination: .terminalTab(tty: "/dev/ttys099")))
    }

    @Test func anyOtherAppIsNoCardButCanBeReturnedTo() async {
        let f = FrontReader(runner: FakeRunner(result: ""), frontApp: { ("com.apple.Notes", "/System/Applications/Notes.app") })
        #expect(await f.read(cards: cards) == FrontState(card: .none, destination: .app(path: "/System/Applications/Notes.app")))
        let nothing = FrontReader(runner: FakeRunner(result: ""), frontApp: { nil })
        #expect(await nothing.read(cards: cards) == FrontState(card: .none, destination: nil))
    }

    @Test func theCardStoreGathersSessionsGistsSitesAndApps() throws {
        let root = try tempDir()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("apps/Notes.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("apps/Spotify.app"), withIntermediateDirectories: true)
        let claude = Fixture.coreDir.appendingPathComponent("claude")
        let index = ArtifactIndex(claudeDir: claude, cacheFile: root.appendingPathComponent("artifact-index.json"), maxAgeDays: 36_500)
        let store = CardStore(configFile: root.appendingPathComponent("config.json"), claudeDir: claude,
                              homeDir: URL(fileURLWithPath: "/Users/sam"), inspector: TableInspector(),
                              catalog: AppCatalog(roots: [root.appendingPathComponent("apps")], extras: []), userNames: ["sam"], artifactIndex: index,
                              chromeTabs: { [(url: "https://claude.ai/artifact/M", title: "Order page sketch | Claude")] },
                              debugFile: root.appendingPathComponent("debug-cards.json"))
        #expect(store.snapshot == CardSnapshot())
        store.rebuild()
        #expect(store.snapshot.artifacts.isEmpty)                       // sessions do not wait for the artifact scan
        store.rebuildArtifacts()
        let snapshot = store.snapshot
        // Only artifacts of sessions that are open now become cards: A, B and C belong to a session that is not open.
        #expect(snapshot.artifacts.map(\.url.lastPathComponent) == ["M", "K"])
        #expect(snapshot.artifacts.last?.title == "Checkout Mock-up")
        #expect(snapshot.artifacts.first?.title == "Order page sketch")          // from the Chrome tab: the session only opened it
        #expect(snapshot.artifacts(of: "sess-101").count == 2)
        // What Jarvis knows is written to a local file, so a wrong pick can be traced to what the cards said.
        let dump = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("debug-cards.json"))) as? [String: Any])
        #expect((dump["tabs"] as? [[String: Any]])?.first?["title"] as? String == "Order page sketch | Claude")
        #expect((dump["artifacts"] as? [[String: Any]])?.count == 2)
        #expect((dump["sessions"] as? [[String: Any]])?.count == 3)
        #expect(snapshot.sessions.map(\.pid) == [101, 102, 106])
        #expect(snapshot.sessions.first?.gist.first == "checkout")
        #expect(snapshot.sessions.first?.replyGist.contains("cart drawer") == true)     // from Claude's replies in that session
        #expect(snapshot.sessions.last?.replyGist == [])
        #expect(snapshot.sessions.last?.gist == [])
        // When a session was last written to: the time its history file changed. It orders the list of all sessions.
        let history = try #require(SessionReader(claudeDir: claude, homeDir: URL(fileURLWithPath: "/Users/sam"), inspector: TableInspector())
            .historyFile(for: snapshot.sessions[0].id))
        let written = try #require(try FileManager.default.attributesOfItem(atPath: history.path)[.modificationDate] as? Date)
        #expect(snapshot.sessions.first?.lastActive == written)
        #expect(snapshot.sessions.last?.lastActive == nil)                              // no history file: not known
        #expect(snapshot.sites.filter { !$0.builtIn }.map(\.name) == ["YouTube", "Gemini"])       // from the settings file, first
        #expect(Array(snapshot.sites.prefix(2)).map(\.name) == ["YouTube", "Gemini"])
        #expect(snapshot.sites.contains { $0.name == "Instagram" && $0.builtIn })               // known without being typed in
        #expect(snapshot.sites.filter { $0.name == "YouTube" }.count == 1)
        #expect(!snapshot.sites.contains { $0.name == "Spotify" })                              // an installed app keeps its name
        // The usual folders are known too, under the home folder this store was given.
        #expect(snapshot.sites.first { $0.name == "Downloads folder" }?.url.path == "/Users/sam/Downloads")
        #expect(snapshot.target(for: snapshot.sites.first { $0.name == "Downloads folder" }!).destination == .folder(path: "/Users/sam/Downloads"))
        #expect(snapshot.apps.map(\.name) == ["Notes", "Spotify"])
    }

    @Test func aRefreshRunsInTheBackgroundAndReplacesTheSnapshot() async throws {
        let root = try tempDir()
        let claude = Fixture.coreDir.appendingPathComponent("claude")
        let index = ArtifactIndex(claudeDir: claude, cacheFile: root.appendingPathComponent("artifact-index.json"), maxAgeDays: 36_500)
        let store = CardStore(configFile: root.appendingPathComponent("config.json"), claudeDir: claude,
                              homeDir: URL(fileURLWithPath: "/Users/sam"), inspector: TableInspector(), catalog: AppCatalog(roots: []),
                              userNames: [], artifactIndex: index)
        store.refresh()
        store.refresh()                               // an overlapping call is merged, not queued up
        for _ in 0..<300 where store.snapshot.sessions.isEmpty || store.snapshot.artifacts.count < 2 { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(store.snapshot.sessions.count == 3)
        #expect(store.snapshot.artifacts.count == 2)
    }

    static let chrome: @Sendable () -> (bundleId: String, path: String)? = { ("com.google.Chrome", "/Applications/Google Chrome.app") }

    @Test func anArtifactTabInChromeIsTheFrontArtifact() async throws {
        let gif = try #require(URL(string: "https://claude.ai/artifact/fixture-gif"))
        for address in ["https://claude.ai/artifact/fixture-gif", "https://claude.ai/artifact/fixture-gif?v=2", "https://claude.ai/artifact/fixture-gif/"] {
            let state = await FrontReader(runner: FakeRunner(result: address), frontApp: Self.chrome).read(cards: cards)
            #expect(state == FrontState(card: .artifact(url: gif), destination: .artifact(url: gif)))
        }
    }

    @Test func anyOtherChromePageIsNoCardButCanBeReturnedTo() async throws {
        let video = "https://www.youtube.com/watch?v=abc"
        let state = await FrontReader(runner: FakeRunner(result: video), frontApp: Self.chrome).read(cards: cards)
        #expect(state == FrontState(card: .none, destination: .artifact(url: try #require(URL(string: video)))))
        // A different artifact whose identifier merely starts the same way is not this card.
        let lookalike = await FrontReader(runner: FakeRunner(result: "https://claude.ai/artifact/fixture-gif2"), frontApp: Self.chrome).read(cards: cards)
        #expect(lookalike.card == .none)
        for odd in ["", "chrome://newtab/"] {
            let state = await FrontReader(runner: FakeRunner(result: odd), frontApp: Self.chrome).read(cards: cards)
            #expect(state == FrontState(card: .none, destination: .app(path: "/Applications/Google Chrome.app")))
        }
    }
}
