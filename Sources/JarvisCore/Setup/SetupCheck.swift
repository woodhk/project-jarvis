import Foundation

public enum CheckStatus: Equatable, Sendable {
    case ok
    /// What the user should do, in one sentence.
    case needsAction(String)
}

/// One line of the setup window.
public struct SetupCheck: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var status: CheckStatus

    public init(id: String, title: String, status: CheckStatus) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// The rules behind each check, kept apart from the code that reads the system so they can be tested.
public enum SetupRules {
    /// `defaultsOutput` is the value of AppleFnUsageType in com.apple.HIToolbox; "0" means "Do Nothing".
    public static func globeKey(defaultsOutput: String?) -> CheckStatus {
        defaultsOutput == "0" ? .ok : .needsAction("In System Settings, Keyboard, set “Press Globe key to” to “Do Nothing”.")
    }

    /// Dictation only gets in the way when it is on and its shortcut is the Globe key pressed twice.
    public static func dictation(enabledOutput: String?, usesGlobeKey: Bool = true) -> CheckStatus {
        enabledOutput == "1" && usesGlobeKey
            ? .needsAction("Apple Dictation is on. Change its shortcut from “Press Globe twice”, or turn Dictation off.")
            : .ok
    }

    /// The Dictation shortcut as macOS stores it: key code, character, modifier flags. Nil when it was never changed
    /// (the default is the Globe key twice). The Globe (fn) modifier flag is 8388608.
    public static func dictationUsesGlobeKey(shortcutParameters: [Int]?) -> Bool {
        guard let parameters = shortcutParameters, parameters.count >= 3 else { return true }
        return parameters[2] & 8_388_608 != 0
    }

    public static func model(exists: Bool) -> CheckStatus {
        exists ? .ok : .needsAction("Run scripts/fetch-model.sh.")
    }

    public static func jevKey(present: Bool) -> CheckStatus {
        present ? .ok : .needsAction("Optional. With a TypeSafe key (scripts/store-key.sh) a session you describe opens directly; without one it is offered as two choices.")
    }

    /// `status` is what macOS answers when asked whether Jarvis may control an app:
    /// 0 allowed, -1743 refused, -1744 not asked yet, -600 the app is not running.
    public static func automation(status: Int32, app: String) -> CheckStatus {
        switch status {
        case -1743: return .needsAction("Allow Jarvis to control \(app) in System Settings, Privacy & Security, Automation.")
        case -1744: return .needsAction("macOS has not asked yet. Press “Check again” and choose Allow when it asks about \(app).")
        default: return .ok
        }
    }

    public static func vscodeAddon(running: Bool, windowsAnswering: Int) -> CheckStatus {
        !running || windowsAnswering > 0
            ? .ok : .needsAction("Run scripts/install-addon.sh, then “Developer: Reload Window” in each VS Code window.")
    }

    /// Checks without which Jarvis does not work. Only these open the setup window by themselves at launch;
    /// the others (Dictation, and permissions macOS asks for on first use) are shown when the window is opened.
    /// The VS Code add-on is not among them: at login VS Code may still be starting it, and a missing add-on is
    /// reported on the pill when it matters. Nor is the TypeSafe key: Jarvis works without one.
    static let essential: Set<String> = ["microphone", "input-monitoring", "globe-key", "model"]

    public static func shouldOpenByItself(_ checks: [SetupCheck]) -> Bool {
        checks.contains { essential.contains($0.id) && $0.status != .ok }
    }
}
