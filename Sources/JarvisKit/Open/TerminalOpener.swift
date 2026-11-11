import Foundation
import JarvisCore

public enum TerminalScripts {
    /// AppleScript that selects the Terminal tab on the given device and brings its window forward.
    /// It returns "ok", or "gone" when no tab is on that device. The window is not moved or resized.
    public static func focusTab(tty: String) throws -> String {
        guard tty.range(of: #"^/dev/ttys[0-9]+$"#, options: .regularExpression) != nil else {
            throw OpenError.failed("Not a terminal device.")
        }
        // Each window is read inside `try`: a window that raises an error when read is skipped.
        return """
        tell application "Terminal"
            with timeout of \(AppleScriptText.timeoutSeconds) seconds
                repeat with w in windows
                    try
                        repeat with t in tabs of w
                            if tty of t is \(AppleScriptText.quoted(tty)) then
                                set selected of t to true
                                if miniaturized of w then set miniaturized of w to false
                                set index of w to 1
                                activate
                                return "ok"
                            end if
                        end repeat
                    end try
                end repeat
                return "gone"
            end timeout
        end tell
        """
    }

    /// AppleScript that returns the device of the tab in front, or an empty string.
    public static let frontTTY = """
    tell application "Terminal"
        with timeout of \(AppleScriptText.timeoutSeconds) seconds
            try
                if (count of windows) is 0 then return ""
                return tty of selected tab of front window
            on error
                return ""
            end try
        end timeout
    end tell
    """
}

/// Opens a Claude Code session that runs in Terminal, down to its tab.
public struct TerminalOpener: Opening {
    private let runner: ScriptRunning

    public init(runner: ScriptRunning) {
        self.runner = runner
    }

    public func open(_ destination: Destination) async throws -> String? {
        guard case .terminalTab(let tty) = destination else { throw OpenError.failed("Not a Terminal tab.") }
        let result = try await runner.run(try TerminalScripts.focusTab(tty: tty))
        if result != "ok" { throw OpenError.gone }
        return nil
    }
}
