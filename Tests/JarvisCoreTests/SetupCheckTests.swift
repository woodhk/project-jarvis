import Foundation
import Testing
@testable import JarvisCore

@Suite struct SetupCheckTests {
    @Test func globeKeyMustBeDoNothing() {
        #expect(SetupRules.globeKey(defaultsOutput: "0") == .ok)
        for v in [nil, "1", "2", "3", ""] as [String?] { #expect(SetupRules.globeKey(defaultsOutput: v) != .ok) }
        #expect(SetupRules.globeKey(defaultsOutput: nil) == .needsAction("In System Settings, Keyboard, set “Press Globe key to” to “Do Nothing”."))
    }

    @Test func dictationIsFlaggedOnlyWhenOn() {
        #expect(SetupRules.dictation(enabledOutput: "1") != .ok)
        #expect(SetupRules.dictation(enabledOutput: "0") == .ok)
        #expect(SetupRules.dictation(enabledOutput: nil) == .ok)
        #expect(SetupRules.dictation(enabledOutput: "1")
            == .needsAction("Apple Dictation is on. Change its shortcut from “Press Globe twice”, or turn Dictation off."))
    }

    @Test func dictationOnAnotherShortcutIsFine() {
        #expect(SetupRules.dictation(enabledOutput: "1", usesGlobeKey: false) == .ok)
        #expect(SetupRules.dictation(enabledOutput: "1", usesGlobeKey: true) != .ok)
        // The shortcut is stored as key code, character and modifier flags; the Globe (fn) flag is 8388608.
        #expect(SetupRules.dictationUsesGlobeKey(shortcutParameters: nil))                       // never changed: the default is Globe twice
        #expect(SetupRules.dictationUsesGlobeKey(shortcutParameters: [65535, 65535, 8_388_608]))
        #expect(!SetupRules.dictationUsesGlobeKey(shortcutParameters: [65535, 65535, 262_144]))  // Control twice
    }

    @Test func missingModelAndKeyNameTheirFix() {
        #expect(SetupRules.model(exists: false) == .needsAction("Run scripts/fetch-model.sh."))
        #expect(SetupRules.jevKey(present: false) == .needsAction("Optional. With a TypeSafe key (scripts/store-key.sh) a session you describe opens directly; without one it is offered as two choices."))
        #expect(SetupRules.model(exists: true) == .ok)
        #expect(SetupRules.jevKey(present: true) == .ok)
    }

    @Test func automationAnswersAreExplained() {
        #expect(SetupRules.automation(status: 0, app: "Terminal") == .ok)
        #expect(SetupRules.automation(status: -600, app: "Terminal") == .ok)                     // not running: nothing to check yet
        #expect(SetupRules.automation(status: -1743, app: "Terminal")
            == .needsAction("Allow Jarvis to control Terminal in System Settings, Privacy & Security, Automation."))
        #expect(SetupRules.automation(status: -1744, app: "Google Chrome")
            == .needsAction("macOS has not asked yet. Press “Check again” and choose Allow when it asks about Google Chrome."))
    }

    @Test func theAddonMattersOnlyWhileVSCodeRuns() {
        #expect(SetupRules.vscodeAddon(running: false, windowsAnswering: 0) == .ok)
        #expect(SetupRules.vscodeAddon(running: true, windowsAnswering: 2) == .ok)
        #expect(SetupRules.vscodeAddon(running: true, windowsAnswering: 0)
            == .needsAction("Run scripts/install-addon.sh, then “Developer: Reload Window” in each VS Code window."))
    }

    @Test func onlyChecksThatStopJarvisWorkingOpenTheWindowByThemselves() {
        let ok = SetupCheck(id: "model", title: "Speech model", status: .ok)
        let dictation = SetupCheck(id: "dictation", title: "Apple Dictation", status: .needsAction("x"))
        let terminal = SetupCheck(id: "terminal-automation", title: "Control Terminal", status: .needsAction("x"))
        let model = SetupCheck(id: "model", title: "Speech model", status: .needsAction("x"))
        // VS Code may still be starting its add-on at login; that must not open a window every time.
        let addon = SetupCheck(id: "vscode-addon", title: "VS Code add-on", status: .needsAction("x"))
        // The TypeSafe key is optional: Jarvis works without one.
        let key = SetupCheck(id: "jev-key", title: "TypeSafe key", status: .needsAction("x"))
        #expect(!SetupRules.shouldOpenByItself([ok, dictation, terminal, addon, key]))
        #expect(SetupRules.shouldOpenByItself([ok, dictation, model]))
    }
}
