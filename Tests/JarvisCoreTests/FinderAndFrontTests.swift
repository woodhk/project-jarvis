import Foundation
import Testing
@testable import JarvisCore

/// From the sixth hand test (log lines 116 to 153). Each test is one thing that went wrong there:
/// "open downloads in Finder" opened Find My; "wait, open Google Chrome" opened the Google website;
/// "can you open the gif artifact?" opened the page of the session in front; "close it" did nothing.
@Suite struct FinderAndFrontTests {
    var b: PickerBench
    var cards: CardSnapshot
    static let base = PickerBench.artifactBase
    let home = URL(fileURLWithPath: "/Users/sam")
    let chrome = AppCard(name: "Google Chrome", aliases: ["Chrome"], path: "/Applications/Google Chrome.app")
    let findMy = AppCard(name: "FindMy", aliases: [], path: "/System/Applications/FindMy.app")
    let finder = AppCard(name: "Finder", aliases: [], path: "/System/Library/CoreServices/Finder.app")
    let music = AppCard(name: "Music", aliases: [], path: "/System/Applications/Music.app")

    init() throws {
        b = try PickerBench()
        cards = b.cards
        cards.apps += [chrome, findMy, finder, music]
        cards.sites = KnownSites.merged(user: cards.sites, apps: cards.apps, folders: KnownFolders.all(home: home))
    }

    func place(_ name: String) -> Target { cards.target(for: cards.sites.first { $0.name == name }!) }

    // MARK: Folders in Finder

    @Test(arguments: ["open downloads in Finder", "can you open my downloads folder", "open the Downloads folder in Finder", "Open Downloads.",
                      "show me my downloads folder in the Finder", "go to downloads", "wait, can you open the downloads folder please"])
    func theDownloadsFolderOpensInFinder(_ phrase: String) async {
        let (p, jev, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: phrase, cards: cards, context: b.idle)
            == .open(Target(destination: .folder(path: "/Users/sam/Downloads"), title: "Downloads folder", subtitle: "Finder",
                            cardKey: "site:Downloads folder")))
        #expect(jev.calls == 0)
    }

    @Test func theUsualFoldersAreKnown() {
        let folders = Dictionary(uniqueKeysWithValues: KnownFolders.all(home: home).map { ($0.name, $0.url.path) })
        #expect(folders["Downloads folder"] == "/Users/sam/Downloads")
        #expect(folders["Documents folder"] == "/Users/sam/Documents")
        #expect(folders["Desktop folder"] == "/Users/sam/Desktop")
        #expect(folders["Pictures folder"] == "/Users/sam/Pictures")
        #expect(folders["Movies folder"] == "/Users/sam/Movies")
        #expect(folders["Music folder"] == "/Users/sam/Music")
        #expect(folders["Applications folder"] == "/Applications")
        #expect(folders["Home folder"] == "/Users/sam")
        #expect(KnownFolders.all(home: home).filter { !$0.builtIn || !$0.url.isFileURL }.isEmpty)
    }

    @Test func anAppKeepsItsNameAndTheFolderKeepsItsOwn() async {
        let (p, _, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "open Music", cards: cards, context: b.idle) == .open(cards.target(for: music)))
        #expect(await p.pick(transcript: "open the music folder", cards: cards, context: b.idle) == .open(place("Music folder")))
        #expect(place("Music folder").destination == .folder(path: "/Users/sam/Music"))
    }

    // What the speech model wrote for "…in Finder": "and find out". The folder is still named in the sentence.
    @Test func aFolderNamedInsideALongerSentenceIsFound() async {
        let (p, _, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "can you open my downloads folder and find out", cards: cards, context: b.idle)
            == .open(place("Downloads folder")))
    }

    @Test func finderItselfOpens() async {
        let (p, jev, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "open Finder", cards: cards, context: b.idle) == .open(cards.target(for: finder)))
        #expect(jev.calls == 0)
    }

    // MARK: Names inside a sentence

    // "find" is two letters short of "FindMy": that is another word, not a slip of the ear.
    @Test func aShortWordIsNotANearMissForALongerName() async {
        var without = cards
        without.apps.removeAll { $0.name == "Finder" }
        #expect(Picker.nearestName(to: ["find"], in: without) == nil)
        #expect(Picker.nearestName(inside: ["can", "you", "find", "out", "what", "is", "open"], in: without) == nil)
        #expect(Picker.nearestName(to: ["crime"], in: without)?.title == "Google Chrome")      // one letter short, two changed: still a slip
        #expect(Picker.nearestName(to: ["chat", "gbt"], in: CardSnapshot(apps: [AppCard(name: "ChatGPT", aliases: [], path: "/Applications/ChatGPT.app")]))?.title == "ChatGPT")
        let (p, _, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "can you find out what is open on my mac right now", cards: without, context: b.idle) == .unknownName)
    }

    // "Google" (the website) and "Google Chrome" (the app) are both in the sentence: the longer name is the one meant.
    @Test func theLongestNameInTheSentenceWins() async {
        #expect(cards.sites.contains { $0.name == "Google" })
        #expect(Picker.nearestName(inside: ["please", "get", "google", "chrome", "up", "for", "me"], in: cards) == cards.target(for: chrome))
        #expect(Picker.nearestName(inside: ["please", "get", "google", "up", "for", "me"], in: cards) == place("Google"))
    }

    @Test func smallTalkBeforeTheRequestIsNotPartOfIt() async {
        #expect(Normalizer.stripLead("wait, open Google Chrome") == "google chrome")
        #expect(Normalizer.stripLead("okay so can you open YouTube") == "youtube")
        #expect(Normalizer.stripLead("oh and then take me to the App Store") == "app store")
        #expect(Normalizer.stripLead("go back to Google Chrome") == "google chrome")
        #expect(Normalizer.stripLead("switch back to Notes") == "notes")
        #expect(Normalizer.stripLead("now playing") == "now playing")                    // no request follows: untouched
        #expect(Normalizer.stripLead("so long session") == "so long session")
        let (p, jev, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "wait, open Google Chrome", cards: cards, context: b.idle) == .open(cards.target(for: chrome)))
        #expect(await p.pick(transcript: "go back to Google Chrome", cards: cards, context: b.idle) == .open(cards.target(for: chrome)))
        #expect(jev.calls == 0)
    }

    // MARK: "Close it"

    @Test(arguments: ["close it", "Can you close it?", "close this", "hide that", "close this app", "close that window", "okay close it please"])
    func closeItMeansTheAppInFront(_ phrase: String) {
        #expect(Picker.appRequest(Normalizer.words(phrase), in: cards) == .appInFront(.hide))
    }

    @Test(arguments: ["quit it", "quit this", "exit that app", "can you quit this one"])
    func quitItMeansTheAppInFront(_ phrase: String) {
        #expect(Picker.appRequest(Normalizer.words(phrase), in: cards) == .appInFront(.quit))
    }

    @Test func sessionsInsideAnAppAreCountedByItsName() {
        let inTerminal = cards.sessions.filter { $0.host == .terminal }.count
        #expect(inTerminal > 0)
        #expect(AppRequest.sessionsInside(appNamed: "Terminal", cards: cards) == inTerminal)
        #expect(AppRequest.sessionsInside(appNamed: "Visual Studio Code", cards: cards) == cards.sessions.filter { $0.host == .vscode }.count)
        #expect(AppRequest.sessionsInside(appNamed: "Code", cards: cards) == cards.sessions.filter { $0.host == .vscode }.count)
        #expect(AppRequest.sessionsInside(appNamed: "Spotify", cards: cards) == 0)
    }

    // MARK: What is in front

    // "Can you open the gif artifact?" was said with another session in front. Jev's yes/no about whether the phrase
    // says which artifact came out at 0.38, so the page of the session in front opened. Whether a phrase names
    // something is plain to see in its words, and is no longer asked of Jev.
    @Test func whatIsInFrontDecidesOnlyWhenThePhraseNamesNothing() async {
        let gif = Self.base + "fixture-gif"
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.9, "s-discovery": 0.1], artifact: [gif: 1.0], known: 0.92, describes: 0.38)
        #expect(await p.pick(transcript: "can you open the gif artifact?", cards: cards, context: b.front("s-discovery"))
            == .open(b.artifactTarget("fixture-gif")))
        // A phrase that names nothing uses what is in front, whatever Jev made of it.
        let (q, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.5, "s-discovery": 0.5], describes: 0.7)
        #expect(await q.pick(transcript: "open the artifact", cards: cards, context: b.front("s-discovery"))
            == .open(b.artifactTarget("fixture-discovery")))
        #expect(b.traces.last?.step == "front")
        // The same for "the terminal for this": a described session is not replaced by the one behind the page in front.
        let (r, _, _) = b.make(kind: "session", session: ["s-share": 0.95, "s-gif": 0.05], describes: 0.3)
        #expect(await r.pick(transcript: "open the open source session", cards: cards, context: b.frontArtifact("fixture-gif"))
            == .open(b.target("s-share")))
    }

    // MARK: The list

    @Test(arguments: ["show your sessions", "show our sessions", "show me the sessions again"])
    func moreWaysToAskForTheList(_ phrase: String) {
        #expect(Picker.asksForList(Normalizer.words(phrase)))
    }
}
