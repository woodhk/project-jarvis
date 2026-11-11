import AppKit
import JarvisCore

/// Opens a Claude Code session that runs in a VS Code terminal: the add-on selects the terminal, then the window
/// that holds it is brought forward by asking VS Code to open what that window already has open.
public struct VSCodeOpener: Opening {
    public typealias Raise = @Sendable (_ path: String) async throws -> Void
    public static let noAddonNote = "The VS Code add-on is not running, so the tab was not selected."
    static let patientTimeoutMs = 1000
    public static let slowNote = "VS Code did not answer in time, so the tab may not be selected."

    private let bridge: VSCodeBridge
    private let raise: Raise

    public init(bridge: VSCodeBridge, raise: @escaping Raise = VSCodeOpener.openInVSCode) {
        self.bridge = bridge
        self.raise = raise
    }

    public func open(_ destination: Destination) async throws -> String? {
        guard case .vscodeTerminal(let shellPid, let folderPath) = destination else { throw OpenError.failed("Not a VS Code terminal.") }
        var result = await bridge.focusResult(shellPid: shellPid)
        if result.owner == nil, result.silent > 0 {
            // A window is there but busy. It may be the owner, so ask once more and wait longer.
            result = await bridge.focusResult(shellPid: shellPid, timeoutMs: Self.patientTimeoutMs)
        }
        if let owner = result.owner {
            try await raise(owner.folders.first ?? folderPath)
            return nil
        }
        if result.silent > 0 {
            // Still no answer from a window that is there: the terminal may exist. Bring the window forward and say so.
            try await raise(folderPath)
            return Self.slowNote
        }
        // Every window answered, and none owns the terminal: it has been closed.
        guard result.answered == 0 else { throw OpenError.gone }
        try await raise(folderPath)
        return Self.noAddonNote
    }

    /// Asks VS Code to open a folder or workspace file. When a window already has it open, VS Code focuses that window.
    public static let openInVSCode: Raise = { path in
        guard let code = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else {
            throw OpenError.failed("Visual Studio Code is not installed.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            if path.isEmpty {
                _ = try await NSWorkspace.shared.openApplication(at: code, configuration: configuration)
            } else {
                _ = try await NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: code, configuration: configuration)
            }
        } catch {
            throw OpenError.failed(error.localizedDescription)
        }
    }
}
