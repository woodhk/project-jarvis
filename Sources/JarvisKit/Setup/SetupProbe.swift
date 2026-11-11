import AppKit
import AVFoundation
import JarvisCore

/// Reads the state of everything Jarvis needs, in the order the setup window shows it.
public struct SetupProbe: Sendable {
    public init() {}

    /// With `askForAutomation`, macOS is allowed to show its "Jarvis wants to control…" question for Terminal and Chrome
    /// (only for an app that is running and has not been asked about yet).
    public func checks(askForAutomation: Bool = false) async -> [SetupCheck] {
        let hiToolbox = UserDefaults(suiteName: "com.apple.HIToolbox")
        let globe = hiToolbox?.object(forKey: "AppleFnUsageType").map { "\($0)" }
        let dictationOn = (UserDefaults(suiteName: "com.apple.assistant.support")?.object(forKey: "Dictation Enabled")
            ?? hiToolbox?.object(forKey: "AppleDictationAutoEnable")).map { "\($0)" }
        let codeRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.VSCode").isEmpty
        let windows = codeRunning ? await VSCodeBridge(socketDir: Paths.vscodeSockets).states().count : 0
        let terminal = await Self.automationStatus(bundleId: "com.apple.Terminal", ask: askForAutomation)
        let chrome = await Self.automationStatus(bundleId: "com.google.Chrome", ask: askForAutomation)
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        return [
            SetupCheck(id: "microphone", title: "Microphone",
                       status: microphone ? .ok : .needsAction("Allow Jarvis in System Settings, Privacy & Security, Microphone.")),
            SetupCheck(id: "input-monitoring", title: "See the fn key",
                       status: CGPreflightListenEventAccess() ? .ok
                           : .needsAction("Allow Jarvis in System Settings, Privacy & Security, Input Monitoring. Then quit and reopen Jarvis.")),
            SetupCheck(id: "globe-key", title: "Globe key does nothing by itself", status: SetupRules.globeKey(defaultsOutput: globe)),
            SetupCheck(id: "dictation", title: "Apple Dictation shortcut",
                       status: SetupRules.dictation(enabledOutput: dictationOn, usesGlobeKey: Self.dictationUsesGlobeKey())),
            SetupCheck(id: "model", title: "Speech model", status: SetupRules.model(exists: FileManager.default.fileExists(atPath: Paths.modelFile.path))),
            SetupCheck(id: "jev-key", title: "TypeSafe key (optional)", status: SetupRules.jevKey(present: KeyStore.jevKey() != nil)),
            SetupCheck(id: "terminal-automation", title: "Control Terminal", status: SetupRules.automation(status: terminal, app: "Terminal")),
            SetupCheck(id: "chrome-automation", title: "Control Google Chrome", status: SetupRules.automation(status: chrome, app: "Google Chrome")),
            SetupCheck(id: "vscode-addon", title: "VS Code add-on", status: SetupRules.vscodeAddon(running: codeRunning, windowsAnswering: windows)),
        ]
    }

    /// The Dictation shortcut is symbolic hot key 164. A shortcut that is switched off cannot get in the way.
    private static func dictationUsesGlobeKey() -> Bool {
        let keys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        guard let entry = keys?["164"] as? [String: Any] else { return SetupRules.dictationUsesGlobeKey(shortcutParameters: nil) }
        if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return false }
        let parameters = ((entry["value"] as? [String: Any])?["parameters"] as? [NSNumber])?.map(\.intValue)
        return SetupRules.dictationUsesGlobeKey(shortcutParameters: parameters)
    }

    /// Asks macOS whether Jarvis may send Apple events to an app. Runs off the main thread: with `ask` it waits for the user.
    private static func automationStatus(bundleId: String, ask: Bool) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
                continuation.resume(returning: status)
            }
        }
    }
}
