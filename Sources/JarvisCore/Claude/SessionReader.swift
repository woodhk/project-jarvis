import Darwin
import Foundation

/// Reads the Claude Code sessions that are open right now, from Claude Code's own files.
/// Those files are internal and can change between versions: this folder is the only place that knows their fields.
public struct SessionReader: Sendable {
    public static let untitled = "untitled session"

    private let claudeDir: URL
    private let homePath: String
    private let inspector: ProcessInspecting

    public init(claudeDir: URL, homeDir: URL, inspector: ProcessInspecting) {
        self.claudeDir = claudeDir
        self.homePath = Self.realPath(homeDir.path)
        self.inspector = inspector
    }

    private struct SessionFile: Decodable {
        var pid: Int32
        var sessionId: String
        var cwd: String
        var name: String?
        var nameSource: String?
    }

    /// One card per live session that runs in Terminal or in a VS Code terminal. `gist` is left empty.
    public func openSessions() -> [SessionCard] {
        let folder = claudeDir.appendingPathComponent("sessions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        // Only "<pid>.json". The folder also holds "<pid>.<hash>.key" files, which are secrets and are never opened.
        let files = names.filter { $0.hasSuffix(".json") && $0.dropLast(5).allSatisfy(\.isNumber) && $0.count > 5 }.sorted()
        return files.compactMap { card(from: folder.appendingPathComponent($0)) }
    }

    private func card(from file: URL) -> SessionCard? {
        guard let data = try? Data(contentsOf: file),
              let session = try? JSONDecoder().decode(SessionFile.self, from: data),
              inspector.isAlive(session.pid),
              let tty = inspector.tty(of: session.pid),
              let shell = inspector.parent(of: session.pid),
              let host = host(of: session.pid) else { return nil }

        let folderPath = Self.realPath(session.cwd)
        let folderLabel = folderPath == homePath ? "home" : URL(fileURLWithPath: folderPath).lastPathComponent
        let userName = session.nameSource == "user" ? session.name?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let label: String
        if let userName, !userName.isEmpty {
            label = userName
        } else {
            // A derived name is never used: it is built from the folder name, and in the home folder that is the user's name.
            label = historyFile(for: session.sessionId).flatMap(TitleScanner.lastTitle(in:)) ?? Self.untitled
        }
        return SessionCard(id: session.sessionId, pid: session.pid, shellPid: shell, tty: tty, host: host,
                           folderPath: folderPath, folderLabel: folderLabel, label: label, gist: [])
    }

    /// Terminal or VS Code, found among up to six ancestors of the process. Any other host is not supported.
    private func host(of pid: Int32) -> HostApp? {
        var current = pid
        for _ in 0..<6 {
            guard let parent = inspector.parent(of: current) else { return nil }
            if let path = inspector.executablePath(of: parent) {
                if path.contains("/Terminal.app/") { return .terminal }
                if path.contains("Visual Studio Code.app/") { return .vscode }
            }
            current = parent
        }
        return nil
    }

    /// The first `projects/*/<sessionId>.jsonl`.
    public func historyFile(for sessionId: String) -> URL? {
        let projects = claudeDir.appendingPathComponent("projects")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        for folder in folders.sorted() {
            let candidate = projects.appendingPathComponent(folder).appendingPathComponent("\(sessionId).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// The path with every symlink resolved. A path that does not exist is returned unchanged.
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
