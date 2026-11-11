import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

/// A folder with a short path: a Unix socket path may be at most 103 bytes, and the usual temporary folder is too deep.
func shortDir() throws -> URL {
    // Tidy up folders left by earlier runs (older than ten minutes).
    let manager = FileManager.default
    for name in (try? manager.contentsOfDirectory(atPath: "/tmp")) ?? [] where name.hasPrefix("jarvis-sock-") {
        let old = "/tmp/" + name
        if let made = (try? manager.attributesOfItem(atPath: old))?[.creationDate] as? Date, made.timeIntervalSinceNow < -600 {
            try? manager.removeItem(atPath: old)
        }
    }
    let dir = URL(fileURLWithPath: "/tmp/jarvis-sock-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Stands in for the add-on in one VS Code window: a real Unix socket server that speaks the same lines of JSON.
final class FakeAddon: @unchecked Sendable {
    let path: String
    private let listener: Int32
    private let owns: [Int32]
    private let active: Int32?
    private let folders: [String]
    private let windowFocused: Bool
    private let silent: Bool
    private let delayMs: UInt32
    private let lock = NSLock()
    private var shown: [Int32] = []

    var focused: [Int32] { lock.withLock { shown } }

    init(dir: URL, pid: Int32, owns: [Int32], active: Int32?, folders: [String] = ["/work/shop"], windowFocused: Bool = true,
         silent: Bool = false, delayMs: UInt32 = 0) throws {
        self.delayMs = delayMs
        path = dir.appendingPathComponent("\(pid).sock").path
        self.owns = owns
        self.active = active
        self.folders = folders
        self.windowFocused = windowFocused
        self.silent = silent
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw CocoaError(.fileWriteInvalidFileName) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 8) == 0 else { throw CocoaError(.fileWriteUnknown) }
        Thread.detachNewThread { [self] in
            while true {
                let connection = accept(listener, nil, nil)
                if connection < 0 { return }
                var on: Int32 = 1          // a reply written after the other side has gone must not raise SIGPIPE
                setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                Thread.detachNewThread { [self] in serve(connection) }
            }
        }
    }

    deinit {
        close(listener)
        unlink(path)
    }

    private func serve(_ connection: Int32) {
        defer { close(connection) }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !received.contains(0x0A) {
            let count = read(connection, &buffer, buffer.count)
            if count <= 0 { return }
            received.append(contentsOf: buffer[0..<count])
        }
        if silent {                                   // hold the connection open and never answer
            _ = read(connection, &buffer, buffer.count)
            return
        }
        let request = (try? JSONSerialization.jsonObject(with: received)) as? [String: Any] ?? [:]
        if delayMs > 0 { usleep(delayMs * 1000) }          // a busy window answers late
        let state: [String: Any] = ["focused": windowFocused, "folders": folders,
                                    "terminals": owns.map { ["shellPid": $0, "name": "zsh"] },
                                    "activeShellPid": active.map { $0 as Any } ?? NSNull()]
        var reply: [String: Any]
        switch request["cmd"] as? String {
        case "state":
            reply = state
        case "focus":
            let wanted = (request["shellPid"] as? NSNumber)?.int32Value ?? -1
            if owns.contains(wanted) {
                lock.withLock { shown.append(wanted) }
                reply = state
                reply["ok"] = true
            } else {
                reply = ["ok": false]
            }
        default:
            reply = ["ok": false, "error": "unknown command"]
        }
        var line = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
        line.append(0x0A)
        line.withUnsafeBytes { _ = write(connection, $0.baseAddress, $0.count) }
    }
}

final class RaiseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var raised: [String] = []
    var paths: [String] { lock.withLock { raised } }
    func add(_ path: String) { lock.withLock { raised.append(path) } }
}

@Suite struct VSCodeBridgeTests {
    @Test func stateAndFocusRoundTrip() async throws {
        let dir = try shortDir()
        let server = try FakeAddon(dir: dir, pid: 77, owns: [4242, 4300], active: 4242)
        let b = VSCodeBridge(socketDir: dir)
        #expect(await b.states() == [VSCodeWindowState(focused: true, folders: ["/work/shop"],
                                                       terminals: [VSCodeTerminal(shellPid: 4242, name: "zsh"), VSCodeTerminal(shellPid: 4300, name: "zsh")],
                                                       activeShellPid: 4242)])
        #expect(try await b.focus(shellPid: 4300).folders == ["/work/shop"])
        #expect(server.focused == [4300])
    }

    @Test func anUnknownTerminalIsGone() async throws {
        let dir = try shortDir()
        let server = try FakeAddon(dir: dir, pid: 77, owns: [1], active: nil)
        await #expect(throws: OpenError.gone) { _ = try await VSCodeBridge(socketDir: dir).focus(shellPid: 2) }
        #expect(server.focused.isEmpty)
        await #expect(throws: OpenError.gone) { _ = try await VSCodeBridge(socketDir: dir.appendingPathComponent("missing")).focus(shellPid: 1) }
    }

    @Test func onlyTheWindowThatOwnsTheTerminalShowsIt() async throws {
        let dir = try shortDir()
        let first = try FakeAddon(dir: dir, pid: 77, owns: [10, 11], active: 10, folders: ["/work/shop"])
        let second = try FakeAddon(dir: dir, pid: 78, owns: [20], active: 20, folders: ["/work/deck"], windowFocused: false)
        let b = VSCodeBridge(socketDir: dir)
        #expect(try await b.focus(shellPid: 20).folders == ["/work/deck"])
        #expect(first.focused.isEmpty)
        #expect(second.focused == [20])
        #expect(await b.states().count == 2)
    }

    @Test func staleAndSilentSocketsAreSkipped() async throws {
        let dir = try shortDir()
        try Data().write(to: dir.appendingPathComponent("5.sock"))                      // a plain file left behind
        let silent = try FakeAddon(dir: dir, pid: 78, owns: [9], active: 9, silent: true)
        let live = try FakeAddon(dir: dir, pid: 77, owns: [4242], active: 4242)
        let began = Date()
        let states = await VSCodeBridge(socketDir: dir).states()
        #expect(Date().timeIntervalSince(began) < 0.4)
        #expect(states.map(\.activeShellPid) == [4242])
        _ = (silent, live)
    }

    @Test func theOpenerSelectsTheTabAndRaisesItsWindow() async throws {
        let dir = try shortDir()
        let server = try FakeAddon(dir: dir, pid: 77, owns: [4300], active: 4300, folders: ["/work/shop.code-workspace", "/work/shop"])
        let log = RaiseLog()
        let opener = VSCodeOpener(bridge: VSCodeBridge(socketDir: dir)) { log.add($0) }
        #expect(try await opener.open(.vscodeTerminal(shellPid: 4300, folderPath: "/elsewhere")) == nil)
        #expect(server.focused == [4300])
        #expect(log.paths == ["/work/shop.code-workspace"])                             // the first path the window reported

        await #expect(throws: OpenError.gone) { _ = try await opener.open(.vscodeTerminal(shellPid: 1, folderPath: "/work/shop")) }
        #expect(log.paths.count == 1)                                                   // a closed terminal raises nothing
        await #expect(throws: OpenError.self) { _ = try await opener.open(.app(path: "/A.app")) }
    }

    @Test func withoutTheAddonTheWindowStillComesForwardWithANote() async throws {
        let log = RaiseLog()
        let opener = VSCodeOpener(bridge: VSCodeBridge(socketDir: try shortDir())) { log.add($0) }
        #expect(try await opener.open(.vscodeTerminal(shellPid: 4300, folderPath: "/work/shop"))
            == "The VS Code add-on is not running, so the tab was not selected.")
        #expect(log.paths == ["/work/shop"])
    }

    @Test func theActiveTerminalOfTheFrontWindowIsTheFrontSession() async throws {
        let cards = try Fixture.cards()
        let share = try #require(cards.sessions.first { $0.id == "s-share" })
        let dir = try shortDir()
        let background = try FakeAddon(dir: dir, pid: 77, owns: [1], active: 1, windowFocused: false)
        let front = try FakeAddon(dir: dir, pid: 78, owns: [share.shellPid, 5], active: share.shellPid)
        let code: FrontReader.FrontApp = { ("com.microsoft.VSCode", "/Applications/Visual Studio Code.app") }
        let reader = FrontReader(runner: FakeRunner(result: ""), bridge: VSCodeBridge(socketDir: dir), frontApp: code)
        #expect(await reader.read(cards: cards) == FrontState(card: .session(id: "s-share"),
                                                             destination: .vscodeTerminal(shellPid: share.shellPid, folderPath: share.folderPath)))
        let noBridge = FrontReader(runner: FakeRunner(result: ""), frontApp: code)
        #expect(await noBridge.read(cards: cards) == FrontState(card: .none, destination: .app(path: "/Applications/Visual Studio Code.app")))
        _ = (background, front)
    }
}
