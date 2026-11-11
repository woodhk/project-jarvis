import Foundation
import Testing
@testable import JarvisCore

enum CoreFixture {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static let claude = dir.appendingPathComponent("claude")
    static let home = URL(fileURLWithPath: "/Users/sam")
}

/// A made-up process table: Terminal (80), VS Code (112), iTerm (121), and the shells and sessions under them.
struct FakeInspector: ProcessInspecting {
    // 107 is alive in Terminal with a tty: if the key file beside the session files were ever read as a session,
    // it would become a card and the tests would see it.
    var alive: Set<Int32> = [80, 90, 100, 101, 102, 104, 105, 106, 107, 110, 111, 112, 120, 121, 130, 131, 200, 201]
    var parents: [Int32: Int32] = [101: 100, 100: 90, 90: 80, 102: 110, 110: 111, 111: 112, 104: 100, 105: 120, 120: 121,
                                   106: 130, 130: 131, 131: 80, 107: 100, 200: 201, 201: 90]
    var ttys: [Int32: String] = [101: "/dev/ttys012", 102: "/dev/ttys013", 105: "/dev/ttys014", 106: "/dev/ttys015", 107: "/dev/ttys017", 200: "/dev/ttys016"]
    var paths: [Int32: String] = [
        80: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", 90: "/usr/bin/login", 131: "/usr/bin/login",
        100: "/bin/zsh", 110: "/bin/zsh", 120: "/bin/zsh", 130: "/bin/zsh", 201: "/bin/zsh",
        111: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper",
        112: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron",
        121: "/Applications/iTerm.app/Contents/MacOS/iTerm2",
    ]
    func isAlive(_ pid: Int32) -> Bool { alive.contains(pid) }
    func parent(of pid: Int32) -> Int32? { parents[pid] }
    func tty(of pid: Int32) -> String? { ttys[pid] }
    func executablePath(of pid: Int32) -> String? { paths[pid] }
}

@Suite struct SessionReaderTests {
    let cards = SessionReader(claudeDir: CoreFixture.claude, homeDir: CoreFixture.home, inspector: FakeInspector()).openSessions()

    @Test func onlyLiveTerminalAndVSCodeSessionsAreRead() {
        #expect(cards.map(\.pid).sorted() == [101, 102, 106])
    }

    @Test func fieldsAreMapped() throws {
        let c = try #require(cards.first { $0.pid == 101 })
        #expect(c.id == "sess-101")
        #expect(c.tty == "/dev/ttys012")
        #expect(c.shellPid == 100)
        #expect(c.host == .terminal)
        #expect(c.folderPath == "/work/shop")
        #expect(c.folderLabel == "shop")
        #expect(c.label == "Checkout page redesign")
        #expect(c.gist == [])
        #expect(cards.first { $0.pid == 102 }?.host == .vscode)
    }

    @Test func aUserNameBeatsTheTitle() {
        #expect(cards.first { $0.pid == 102 }?.label == "launch-video")
    }

    @Test func noTitleGivesThePlaceholderNotTheDerivedName() throws {
        let c = try #require(cards.first { $0.pid == 106 })
        #expect(c.label == "untitled session")
        #expect(c.folderLabel == "home")
    }

    @Test func aSymlinkedFolderIsResolved() throws {
        let root = try tempDir()
        let real = root.appendingPathComponent("code/shop"), link = root.appendingPathComponent("desktop-shop")
        let claude = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claude.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let file = #"{"pid":200,"sessionId":"sess-200","cwd":"\#(link.path)","name":"x","nameSource":"derived"}"#
        try Data(file.utf8).write(to: claude.appendingPathComponent("sessions/200.json"))
        let found = SessionReader(claudeDir: claude, homeDir: root, inspector: FakeInspector()).openSessions()
        #expect(found.map(\.folderPath) == [real.path])
        #expect(found.map(\.folderLabel) == ["shop"])
    }

    @Test func aMissingSessionsFolderGivesNoCards() throws {
        #expect(SessionReader(claudeDir: try tempDir(), homeDir: CoreFixture.home, inspector: FakeInspector()).openSessions().isEmpty)
    }

    @Test func theLastShortTitleLineWins() {
        let history = CoreFixture.claude.appendingPathComponent("projects/-work-shop/sess-101.jsonl")
        #expect(TitleScanner.lastTitle(in: history) == "Checkout page redesign")
        #expect(TitleScanner.lastTitle(in: CoreFixture.claude.appendingPathComponent("projects/-work-shop/sess-102.jsonl")) == "launch-video")
        #expect(TitleScanner.lastTitle(in: CoreFixture.claude.appendingPathComponent("projects/-work-shop/none.jsonl")) == nil)
    }

    @Test func theLiveInspectorSeesThisProcess() {
        let live = LiveProcessInspector()
        #expect(live.isAlive(getpid()))
        #expect(live.parent(of: getpid()) == getppid())
        #expect(live.executablePath(of: getpid())?.isEmpty == false)
        #expect(!live.isAlive(999_999))
    }

    /// Terminal starts shells through `login`, which belongs to root. Its parent must still be readable,
    /// or sessions in Terminal are never traced back to Terminal.
    @Test func theAncestryIsReadableThroughProcessesOwnedByRoot() {
        let live = LiveProcessInspector()
        var current = getpid()
        var steps = 0
        while current != 1, steps < 32, let parent = live.parent(of: current) {
            current = parent
            steps += 1
        }
        #expect(current == 1)
    }
}
