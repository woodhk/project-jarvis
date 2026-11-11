import Foundation
import Testing
@testable import JarvisCore

@Suite struct NameMatcherTests {
    let m = NameMatcher(
        apps: [AppCard(name: "ChatGPT", aliases: [], path: "/Applications/ChatGPT.app"),
               AppCard(name: "Visual Studio Code", aliases: ["vs code"], path: "/Applications/Visual Studio Code.app")],
        sites: Config.default.sites)

    @Test func speechSpellingStillMatches() {
        #expect(m.match("Open Chat GPT.")?.destination == .app(path: "/Applications/ChatGPT.app"))
    }

    @Test func sitesMatch() {
        #expect(m.match("open YouTube")?.destination == .site(url: URL(string: "https://www.youtube.com/")!))
        #expect(m.match("Open up Gemini please")?.title == "Gemini")
    }

    @Test func aliasesMatch() {
        #expect(m.match("switch to VS Code")?.title == "Visual Studio Code")
        #expect(m.match("open you tube")?.title == "YouTube")
    }

    @Test func describedThingsDoNotMatch() {
        #expect(m.match("open the open source insta to comment session") == nil)
        #expect(m.match("open") == nil)
        #expect(m.match("open the artifact") == nil)
    }

    @Test func leadInsAndPoliteEndingsAreStripped() {
        #expect(Normalizer.stripLead("Take me to the YouTube website, please.") == "youtube")
        #expect(Normalizer.stripLead("Bring up my Chat GPT app") == "chat gpt")
        #expect(Normalizer.stripLead("open the App Store") == "app store")
        #expect(Normalizer.stripLead("YouTube") == "youtube")
        #expect(Normalizer.words("Insta-comment_dm, what's NEW?") == ["insta", "comment", "dm", "whats", "new"])
        #expect(Normalizer.compact("Chat GPT.") == "chatgpt")
    }

    @Test func targetsSayWhereTheThingLives() {
        let cards = CardSnapshot()
        let site = cards.target(for: Config.default.sites[0])
        #expect(site == Target(destination: .site(url: URL(string: "https://www.youtube.com/")!), title: "YouTube", subtitle: "Chrome", cardKey: "site:YouTube"))
        let app = cards.target(for: AppCard(name: "ChatGPT", aliases: [], path: "/Applications/ChatGPT.app"))
        #expect(app == Target(destination: .app(path: "/Applications/ChatGPT.app"), title: "ChatGPT", subtitle: "app", cardKey: "app:/Applications/ChatGPT.app"))
        let inTerminal = SessionCard(id: "a", pid: 2, shellPid: 1, tty: "/dev/ttys004", host: .terminal, folderPath: "/work/shop", folderLabel: "shop", label: "Checkout", gist: [])
        #expect(cards.target(for: inTerminal) == Target(destination: .terminalTab(tty: "/dev/ttys004"), title: "Checkout", subtitle: "Terminal · shop", cardKey: "session:a"))
        var inCode = inTerminal
        inCode.host = .vscode
        #expect(cards.target(for: inCode) == Target(destination: .vscodeTerminal(shellPid: 1, folderPath: "/work/shop"), title: "Checkout", subtitle: "VS Code · shop", cardKey: "session:a"))
    }
}
