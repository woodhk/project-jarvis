import AppKit
import JarvisCore

public enum AppControlResult: Equatable, Sendable {
    /// Hidden, or quit and gone.
    case done
    /// Asked to quit and still there a moment later: most likely it is asking about unsaved work.
    case asked
    case notRunning
    case failed
}

/// Hides and quits running apps.
public protocol AppControlling: Sendable {
    /// The app in front right now: what "close it" means.
    func frontApp() -> (name: String, path: String)?
    func isRunning(path: String) -> Bool
    /// Takes the app's windows off the screen. The app keeps running and nothing in it is closed.
    func hide(path: String) async -> AppControlResult
    /// Asks the app to quit in the normal way. It is never forced, so it can still ask about unsaved work.
    func quit(path: String) async -> AppControlResult
}

public struct LiveAppControl: AppControlling {
    /// How long a quit is watched before it is reported as "asked".
    static let quitWait: TimeInterval = 1.5

    public init() {}

    /// The running copies of the app at this path. Apps are compared by their identifier first: macOS runs some
    /// system apps from a different place on disk than the folder they are listed in.
    static func running(path: String) -> [NSRunningApplication] {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let identifier = Bundle(url: url)?.bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            if let identifier, app.bundleIdentifier == identifier { return true }
            return app.bundleURL?.resolvingSymlinksInPath().path == url.path
        }
    }

    public func frontApp() -> (name: String, path: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication, let url = app.bundleURL else { return nil }
        return (app.localizedName ?? url.deletingPathExtension().lastPathComponent, url.path)
    }

    public func isRunning(path: String) -> Bool {
        !Self.running(path: path).isEmpty
    }

    public func hide(path: String) async -> AppControlResult {
        let apps = Self.running(path: path)
        guard !apps.isEmpty else { return .notRunning }
        if apps.map({ $0.hide() }).contains(true) { return .done }
        // macOS does not always answer "yes" even when the app then goes (seen with Calculator), so the answer is
        // what happened, not what was returned.
        for _ in 0..<12 {
            if apps.contains(where: \.isHidden) { return .done }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return .failed
    }

    public func quit(path: String) async -> AppControlResult {
        let apps = Self.running(path: path)
        guard !apps.isEmpty else { return .notRunning }
        let pids = apps.map(\.processIdentifier)
        let accepted = apps.map { $0.terminate() }.contains(true)
        // Whether the app has gone is asked of the system directly: the app objects only learn of it later.
        func gone() -> Bool { pids.allSatisfy { kill($0, 0) != 0 && errno == ESRCH } }
        let deadline = Date().addingTimeInterval(Self.quitWait)
        while Date() < deadline {
            if gone() { return .done }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if gone() { return .done }
        return accepted ? .asked : .failed
    }
}
