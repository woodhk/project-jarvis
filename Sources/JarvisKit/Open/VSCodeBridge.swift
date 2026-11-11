import Foundation
import JarvisCore

public struct VSCodeTerminal: Equatable, Codable, Sendable {
    public var shellPid: Int32
    public var name: String
}

/// What one VS Code window reports about itself.
public struct VSCodeWindowState: Equatable, Codable, Sendable {
    public var focused: Bool
    /// The saved workspace file first, when there is one, then the folders. Opening the first brings the window forward.
    public var folders: [String]
    public var terminals: [VSCodeTerminal]
    public var activeShellPid: Int32?
}

/// Talks to the Jarvis add-on in each VS Code window. Every window listens on its own Unix socket in `socketDir`;
/// a message is one line of JSON and the answer is one line of JSON. A window that does not answer in time is skipped.
public struct VSCodeBridge: Sendable {
    private let socketDir: URL
    private let timeoutMs: Int

    public init(socketDir: URL, timeoutMs: Int = 150) {
        self.socketDir = socketDir
        self.timeoutMs = timeoutMs
    }

    /// One state per window that answers in time.
    public func states() async -> [VSCodeWindowState] {
        await ask(["cmd": "state"], timeoutMs: timeoutMs).replies.compactMap { try? JSONDecoder().decode(VSCodeWindowState.self, from: $0) }
    }

    /// Selects the terminal whose shell has this process id, in the window that owns it.
    /// Throws `OpenError.gone` when no window owns that terminal.
    public func focus(shellPid: Int32) async throws -> VSCodeWindowState {
        guard let owner = await focusResult(shellPid: shellPid).owner else { throw OpenError.gone }
        return owner
    }

    /// The owner's state if a window took the request; how many windows answered at all; and how many are there
    /// (they accepted the connection) but did not answer in time. A slow window may well be the owner.
    func focusResult(shellPid: Int32, timeoutMs: Int? = nil) async -> (owner: VSCodeWindowState?, answered: Int, silent: Int) {
        let result = await ask(["cmd": "focus", "shellPid": shellPid], timeoutMs: timeoutMs ?? self.timeoutMs)
        let owner = result.replies.first { reply in
            ((try? JSONSerialization.jsonObject(with: reply)) as? [String: Any])?["ok"] as? Bool == true
        }
        return (owner.flatMap { try? JSONDecoder().decode(VSCodeWindowState.self, from: $0) }, result.replies.count, result.silent)
    }

    private enum Exchange {
        case reply(Data)
        /// Connected, but no answer within the time limit.
        case silent
        /// No add-on behind this socket (a stale file, or not a socket).
        case unreachable
    }

    /// Sends the request to every socket at once and gathers the answers that arrive in time.
    private func ask(_ request: [String: Any], timeoutMs limit: Int) async -> (replies: [Data], silent: Int) {
        guard var line = try? JSONSerialization.data(withJSONObject: request) else { return ([], 0) }
        line.append(0x0A)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: socketDir.path)) ?? []).filter { $0.hasSuffix(".sock") }.sorted()
        let message = line
        return await withTaskGroup(of: (Int, Exchange).self) { group in
            for (index, name) in names.enumerated() {
                let path = socketDir.appendingPathComponent(name).path
                group.addTask {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            continuation.resume(returning: (index, Self.exchange(path: path, message: message, timeoutMs: limit)))
                        }
                    }
                }
            }
            var replies: [(Int, Data)] = []
            var silent = 0
            for await (index, exchange) in group {
                switch exchange {
                case .reply(let data): replies.append((index, data))
                case .silent: silent += 1
                case .unreachable: break
                }
            }
            return (replies.sorted { $0.0 < $1.0 }.map(\.1), silent)
        }
    }

    /// One request and one answer over a Unix socket, with a deadline.
    private static func exchange(path: String, message: Data, timeoutMs: Int) -> Exchange {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .unreachable }
        defer { close(descriptor) }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return .unreachable }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return .unreachable }
        let sent = message.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard sent == message.count else { return .unreachable }

        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            if let end = received.firstIndex(of: 0x0A) { return .reply(received.prefix(upTo: end)) }
            let remaining = Int32((deadline.timeIntervalSinceNow * 1000).rounded(.up))
            guard remaining > 0 else { return .silent }
            var waiting = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&waiting, 1, remaining) > 0 else { return .silent }
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return .unreachable }
            received.append(contentsOf: buffer[0..<count])
        }
    }
}
