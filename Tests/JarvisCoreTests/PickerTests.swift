import Foundation
import Testing
@testable import JarvisCore

@Suite struct PickerTests {
    let b: PickerBench
    var cards: CardSnapshot { b.cards }

    init() throws { b = try PickerBench() }

    @Test func aNameNeverReachesJev() async {
        let (p, jev, _) = b.make()
        #expect(await p.pick(transcript: "open YouTube", cards: cards, context: b.idle) == .open(cards.target(for: cards.sites[0])))
        #expect(jev.calls == 0)
        #expect(b.traces.last?.step == "name")
    }

    @Test func controlWords() async {
        let (p, jev, _) = b.make()
        #expect(await p.pick(transcript: "Back.", cards: cards, context: b.idle) == .back)
        #expect(await p.pick(transcript: "go back", cards: cards, context: b.idle) == .back)
        #expect(await p.pick(transcript: "Two.", cards: cards, context: b.choosing) == .pickChoice(1))
        #expect(await p.pick(transcript: "to", cards: cards, context: b.choosing) == .pickChoice(1))
        #expect(await p.pick(transcript: "second", cards: cards, context: b.choosing) == .pickChoice(1))
        #expect(await p.pick(transcript: "first", cards: cards, context: b.choosing) == .pickChoice(0))
        #expect(await p.pick(transcript: "One.", cards: cards, context: b.choosing) == .pickChoice(0))
        #expect(jev.calls == 0)
        #expect(b.traces.last?.step == "control")
    }

    @Test func choiceWordsMeanNothingSpecialWhenNoChoicesShow() async {
        let (p, jev, _) = b.make(session: ["s-share": 0.9])
        #expect(await p.pick(transcript: "two", cards: cards, context: b.idle) == .open(b.target("s-share")))
        #expect(jev.calls == 1)
    }

    @Test func aSureSessionOpens() async {
        let (p, _, _) = b.make(session: ["s-share": 0.98, "s-ideas": 0.02])
        #expect(await p.pick(transcript: "open the open source insta to comment session", cards: cards, context: b.idle) == .open(b.target("s-share")))
        #expect(b.traces.last?.step == "jev")
        #expect(b.traces.last?.kind == "session")
    }

    @Test func vsCodeAndTerminalSessionsGetTheRightDestination() {
        let share = b.session("s-share"), discovery = b.session("s-discovery")
        #expect(b.target("s-share").destination == .vscodeTerminal(shellPid: share.shellPid, folderPath: share.folderPath))
        #expect(b.target("s-discovery").destination == .terminalTab(tty: discovery.tty))
    }

    @Test func anUnsureSessionOffersTwo() async {
        let (p, _, _) = b.make(session: ["s-ideas": 0.51, "s-share": 0.49])
        #expect(await p.pick(transcript: "open the insta session", cards: cards, context: b.idle)
            == .choices([b.target("s-ideas"), b.target("s-share")], rememberable: true))
    }

    @Test func exactlyTheThresholdOpens() async {
        let (p, _, _) = b.make(session: ["s-ideas": 0.80, "s-share": 0.20])
        #expect(await p.pick(transcript: "open the insta session", cards: cards, context: b.idle) == .open(b.target("s-ideas")))
        let (q, _, _) = b.make(session: ["s-ideas": 0.79, "s-share": 0.21])
        #expect(await q.pick(transcript: "open the insta session", cards: cards, context: b.idle)
            == .choices([b.target("s-ideas"), b.target("s-share")], rememberable: true))
    }

    @Test func theFrontSessionIsNotOfferedForSessionRequests() async {
        let (p, jev, _) = b.make(session: ["s-front": 0.86, "s-discovery": 0.07], other: ["s-discovery": 0.85, "s-ideas": 0.15])
        #expect(await p.pick(transcript: "open the discovery session", cards: cards, context: b.front("s-front")) == .open(b.target("s-discovery")))
        #expect(jev.lastFront == .session(id: "s-front"))
    }

    @Test func notKnownMeansNothing() async {
        let (p, _, _) = b.make(session: ["s-chip": 0.28, "s-share": 0.26], known: 0.04)
        #expect(await p.pick(transcript: "open the session about my tax return", cards: cards, context: b.idle) == .nothing)
    }

    @Test func noSessionsAtAllMeansNothing() async {
        let (p, _, _) = b.make(session: [:])
        #expect(await p.pick(transcript: "open the gif session", cards: cards, context: b.idle) == .nothing)
        let (q, _, _) = b.make(session: ["closed-since": 0.9])          // an answer for a card that no longer exists
        #expect(await q.pick(transcript: "open the gif session", cards: cards, context: b.idle) == .nothing)
    }

    @Test func jevFailuresFallBackToTwoChoices() async {
        for e in [JevError.timeout, .noKey, .http(401), .malformed] {
            let (p, _, _) = b.make(error: e)
            #expect(await p.pick(transcript: "open the gif library", cards: cards, context: b.idle) == .choices([b.target("s-gif")], rememberable: false))
            #expect(b.traces.last?.step == "fallback")
        }
    }

    @Test func theFallbackOffersTheTwoBestMatches() async {
        let (p, _, _) = b.make(error: .timeout)
        #expect(await p.pick(transcript: "open the instagram reel tracking session", cards: cards, context: b.idle)
            == .choices([b.target("s-ideas"), b.target("s-front")], rememberable: false))
        // "insta" also counts as the start of "instagram"; equal scores keep the order of the cards.
        #expect(FallbackMatcher.rank("open the insta thing", cards: cards).map(\.cardKey) == ["session:s-ideas", "session:s-front", "session:s-share"])
    }

    @Test func fallbackWithNoSharedWordsIsNothing() async {
        let (p, _, _) = b.make(error: .timeout)
        #expect(await p.pick(transcript: "open my tax return", cards: cards, context: b.idle) == .nothing)
    }

    @Test func aRememberedPhraseSkipsJev() async {
        let (p, jev, _) = b.make(remembered: ["open the insta session": "session:s-share"])
        #expect(await p.pick(transcript: "Open the insta session.", cards: cards, context: b.idle) == .open(b.target("s-share")))
        #expect(jev.calls == 0)
        #expect(b.traces.last?.step == "remembered")
    }

    @Test func aRememberedPhraseForAClosedSessionIsForgotten() async {
        let (p, jev, store) = b.make(session: ["s-share": 0.9], remembered: ["open the insta session": "session:gone"])
        #expect(await p.pick(transcript: "open the insta session", cards: cards, context: b.idle) == .open(b.target("s-share")))
        #expect(jev.calls == 1)
        #expect(store.cardKey(for: "open the insta session") == nil)
    }

    @Test func aMisheardAppNameStillOpens() async {
        let (p, _, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "open chat gbt", cards: cards, context: b.idle) == .open(cards.target(for: cards.apps[0])))
        #expect(await p.pick(transcript: "open spreadsheets", cards: cards, context: b.idle) == .unknownName)
        #expect(await p.pick(transcript: "open you two", cards: cards, context: b.idle) == .unknownName)      // too far from "YouTube" for its length
    }

    @Test func preparingWarmsTheConnection() {
        let (p, jev, _) = b.make()
        p.prepare()
        #expect(jev.warmCalls == 1)
    }
}

extension PickerTests {
    // Review finding 10: with two sessions open and one in front, a session request must not lead back to the one in front.
    @Test func withTwoSessionsTheOneInFrontIsStillLeftOut() async {
        var two = b
        two.cards.sessions = Array(b.cards.sessions.prefix(2))                  // s-ideas, s-discovery
        let (p, _, _) = two.make(kind: "session", session: ["s-ideas": 0.9, "s-discovery": 0.1])
        #expect(await p.pick(transcript: "open the other reel session", cards: two.cards, context: two.front("s-ideas"))
            == .choices([two.target("s-discovery")], rememberable: true))
    }

    // People answer two choices in their own words. Short answers that name a number count.
    @Test func choicesCanBeAnsweredInNaturalWords() async {
        let (p, jev, _) = b.make()
        for (said, index) in [("The second one.", 1), ("number two", 1), ("Second, please", 1), ("the first one", 0), ("option one", 0), ("Number 1", 0)] {
            #expect(await p.pick(transcript: said, cards: cards, context: b.choosing) == .pickChoice(index), "\(said)")
        }
        #expect(jev.calls == 0)
        let (q, asked, _) = b.make(session: ["s-share": 0.9])
        #expect(await q.pick(transcript: "open the second insta session that I use", cards: cards, context: b.choosing) == .open(b.target("s-share")))
        #expect(asked.calls == 1)                                               // a longer sentence is a new request
        #expect(await q.pick(transcript: "the second one", cards: cards, context: b.idle) == .open(b.target("s-share")))   // not choosing: no special meaning
    }
}

extension PickerTests {
    // From the first hand test: Whisper wrote "open chat, jbt" and "open chat GBT" for ChatGPT. A short phrase
    // that is nearly an app's name opens the app, without asking Jev (which once took "chat" to mean a session).
    @Test func aNearlyRightAppNameOpensWithoutJev() async {
        let (p, jev, _) = b.make(session: ["s-share": 0.63, "s-ideas": 0.19])
        for heard in ["open chat, jbt", "Open chat GBT.", "open Chat G P T"] {
            #expect(await p.pick(transcript: heard, cards: cards, context: b.idle) == .open(cards.target(for: cards.apps[0])), "\(heard)")
        }
        #expect(jev.calls == 0)
        #expect(b.traces.last?.step == "name")
        #expect(await p.pick(transcript: "open the gif session", cards: cards, context: b.idle) == .choices([b.target("s-share"), b.target("s-ideas")], rememberable: true))
        #expect(jev.calls == 1)                                                  // a described session still goes to Jev
    }

    @Test func anAppNamedInsideALongerSentenceIsFound() async {
        let (p, _, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "OpenChat GBT in the desktop app", cards: cards, context: b.idle) == .open(cards.target(for: cards.apps[0])))
        #expect(await p.pick(transcript: "can you bring up the you tube website for me", cards: cards, context: b.idle) == .open(cards.target(for: cards.sites[0])))
        #expect(await p.pick(transcript: "open the spreadsheet thing for me", cards: cards, context: b.idle) == .unknownName)
        #expect(Normalizer.stripLead("OpenChat GBT") == "chat gbt")
        #expect(Normalizer.stripLead("can you open the YouTube website") == "youtube")
    }
}

@Suite struct RememberedStoreTests {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-remembered-\(UUID().uuidString)/remembered.json")

    @Test func phrasesAreMatchedWithoutCaseSpacesOrPunctuation() {
        let store = RememberedStore(file: file)
        store.remember("Open the insta session.", cardKey: "session:s-share")
        #expect(store.cardKey(for: "open the Insta  session") == "session:s-share")
        #expect(store.cardKey(for: "open the other session") == nil)
    }

    @Test func choicesSurviveARestart() {
        RememberedStore(file: file).remember("open the insta session", cardKey: "session:s-share")
        #expect(RememberedStore(file: file).cardKey(for: "open the insta session") == "session:s-share")
        RememberedStore(file: file).forget("Open the insta session")
        #expect(RememberedStore(file: file).cardKey(for: "open the insta session") == nil)
    }

    @Test func aDamagedFileStartsEmptyAndIsReplacedOnTheNextChange() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        let store = RememberedStore(file: file)
        #expect(store.cardKey(for: "anything") == nil)
        store.remember("open the gif session", cardKey: "session:s-gif")
        #expect(RememberedStore(file: file).cardKey(for: "open the gif session") == "session:s-gif")
    }
}
