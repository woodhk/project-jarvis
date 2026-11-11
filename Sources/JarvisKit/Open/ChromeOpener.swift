import Foundation
import JarvisCore

public enum ChromeScripts {
    private static let hostHandler = """
    on hostOf(u)
        set AppleScript's text item delimiters to "://"
        if (count of text items of u) < 2 then
            set AppleScript's text item delimiters to ""
            return ""
        end if
        set r to text item 2 of u
        set AppleScript's text item delimiters to "/"
        set h to text item 1 of r
        set AppleScript's text item delimiters to ""
        if h starts with "www." and (count of h) > 4 then set h to text 5 thru -1 of h
        return h
    end hostOf

    """

    /// AppleScript that switches to a matching Chrome tab, or opens the address in a new tab when there is none.
    /// A site matches a tab on the same host (a leading "www." is ignored). An artifact matches a tab whose address starts with its link.
    public static func focusOrOpen(_ destination: Destination) throws -> String {
        let url: URL
        let setup: String
        let test: String
        switch destination {
        case .site(let site):
            url = site
            var host = (site.host ?? "").lowercased()
            if host.hasPrefix("www.") { host.removeFirst(4) }
            guard !host.isEmpty else { throw OpenError.failed("The website has no host name.") }
            setup = "set wantedHost to \(AppleScriptText.quoted(host))"
            test = "my hostOf(URL of t) is wantedHost"
        case .artifact(let artifact):
            url = artifact
            setup = ""
            test = "(URL of t) starts with \(AppleScriptText.quoted(artifact.absoluteString))"
        default:
            throw OpenError.failed("Not a Chrome destination.")
        }
        let address = AppleScriptText.quoted(url.absoluteString)
        return hostHandler + """
        tell application "Google Chrome"
            with timeout of \(AppleScriptText.timeoutSeconds) seconds
            \(setup)
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    if \(test) then
                        set active tab index of w to i
                        if minimized of w then set minimized of w to false
                        set index of w to 1
                        activate
                        return "focused"
                    end if
                end repeat
            end repeat
            if (count of windows) is 0 then
                make new window
                set URL of active tab of front window to \(address)
            else
                tell front window to make new tab with properties {URL:\(address)}
            end if
            activate
            return "opened"
            end timeout
        end tell
        """
    }

    /// AppleScript that returns the address of the tab in front, or an empty string.
    public static let frontURL = """
    tell application "Google Chrome"
        with timeout of \(AppleScriptText.timeoutSeconds) seconds
            if (count of windows) is 0 then return ""
            return URL of active tab of front window
        end timeout
    end tell
    """
}

extension ChromeScripts {
    /// AppleScript that lists the Chrome tabs showing a claude.ai page: one line per tab, address, a tab character, title.
    public static let claudeTabs = """
    set fieldBreak to character id 9
    set lineBreak to character id 10
    tell application "Google Chrome"
        with timeout of \(AppleScriptText.timeoutSeconds) seconds
            set found to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if u contains "claude.ai/" then set found to found & u & fieldBreak & (title of t) & lineBreak
                end repeat
            end repeat
            return found
        end timeout
    end tell
    """

    public static func parseTabs(_ output: String) -> [(url: String, title: String)] {
        output.split(separator: "\n").compactMap { line -> (url: String, title: String)? in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard let url = parts.first, !url.isEmpty else { return nil }
            return (String(url), parts.count > 1 ? String(parts[1]) : "")
        }
    }
}

/// Opens websites and artifacts in Google Chrome.
public struct ChromeOpener: Opening {
    private let runner: ScriptRunning

    public init(runner: ScriptRunning) {
        self.runner = runner
    }

    public func open(_ destination: Destination) async throws -> String? {
        _ = try await runner.run(try ChromeScripts.focusOrOpen(destination))
        return nil
    }
}
