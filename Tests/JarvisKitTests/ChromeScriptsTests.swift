import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

@Suite struct ChromeScriptsTests {
    @Test func siteScriptMatchesByHost() throws {
        let s = try ChromeScripts.focusOrOpen(.site(url: URL(string: "https://www.youtube.com/")!))
        #expect(s.contains("\"youtube.com\""))
        #expect(s.contains("\"https://www.youtube.com/\""))
    }

    @Test func artifactScriptMatchesByPrefix() throws {
        #expect(try ChromeScripts.focusOrOpen(.artifact(url: URL(string: "https://claude.ai/artifact/abc")!))
            .contains("starts with \"https://claude.ai/artifact/abc\""))
    }

    @Test func onlyChromeDestinationsAreAccepted() {
        #expect(throws: OpenError.self) { try ChromeScripts.focusOrOpen(.app(path: "/Applications/ChatGPT.app")) }
    }

    @Test func quotesInAnAddressCannotEndTheString() throws {
        let s = try ChromeScripts.focusOrOpen(.artifact(url: URL(string: "https://claude.ai/artifact/a%22b")!))
        #expect(!s.contains("a\"b"))
        #expect(AppleScriptText.quoted("say \"hi\" \\ bye") == "\"say \\\"hi\\\" \\\\ bye\"")
    }

    @Test func theOpenerRoutesEachKindOfDestination() async throws {
        let terminal = FakeOpener(), vscode = FakeOpener(), chrome = FakeOpener(), app = FakeOpener()
        let all = CompositeOpener(terminal: terminal, vscode: vscode, chrome: chrome, app: app)
        let url = URL(string: "https://www.youtube.com/")!
        for d in [Destination.terminalTab(tty: "/dev/ttys001"), .vscodeTerminal(shellPid: 1, folderPath: "/w"), .site(url: url), .artifact(url: url), .app(path: "/A.app")] {
            _ = try await all.open(d)
        }
        #expect(terminal.opened == [.terminalTab(tty: "/dev/ttys001")])
        #expect(vscode.opened == [.vscodeTerminal(shellPid: 1, folderPath: "/w")])
        #expect(chrome.opened == [.site(url: url), .artifact(url: url)])
        #expect(app.opened == [.app(path: "/A.app")])
        let partial = CompositeOpener(terminal: nil, vscode: nil, chrome: chrome, app: app)
        await #expect(throws: OpenError.self) { _ = try await partial.open(.terminalTab(tty: "/dev/ttys001")) }
    }

    /// Compiles the scripts with macOS's own compiler (nothing is run, and Chrome is not started), so a wrong word is caught here.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app")))
    func theScriptsAreValidAppleScript() throws {
        let scripts = [try ChromeScripts.focusOrOpen(.site(url: URL(string: "https://www.youtube.com/")!)),
                       try ChromeScripts.focusOrOpen(.artifact(url: URL(string: "https://claude.ai/artifact/abc")!)),
                       ChromeScripts.frontURL]
        for script in scripts { #expect(try compiles(script)) }
        #expect(try !compiles("tell application \"Google Chrome\" to set the the"))   // the check does reject a bad script
    }
}
