import Foundation

public enum AppleScriptText {
    /// Every script waits at most this long for an app to answer. All scripts share one queue, so a script that
    /// waited for ever would hold up every later request.
    public static let timeoutSeconds = 3

    /// A string as an AppleScript literal, with quotes and backslashes escaped.
    public static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Runs AppleScript inside the app, one script at a time, off the main thread.
public struct AppleScriptRunner: ScriptRunning {
    private static let queue = DispatchQueue(label: "local.jarvis.switcher.applescript", qos: .userInitiated)

    public init() {}

    public func run(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(number)"
                    let app = error[NSAppleScript.errorAppName] as? String ?? "that app"
                    // -1743: the user has not allowed Jarvis to control the app (Privacy & Security, Automation).
                    // -1712: the app did not answer within the script's time limit.
                    continuation.resume(throwing: number == -1743 ? OpenError.notPermitted(app)
                        : OpenError.failed(number == -1712 ? "\(app) did not answer in time." : message))
                } else {
                    continuation.resume(returning: result?.stringValue ?? "")
                }
            }
        }
    }
}
