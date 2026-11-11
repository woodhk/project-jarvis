import Foundation
import Testing
@testable import JarvisCore

@Suite struct PickerArtifactTests {
    var b: PickerBench
    var cards: CardSnapshot { b.cards }
    static let base = PickerBench.artifactBase

    init() throws { b = try PickerBench() }

    @Test func onlySessionsWithArtifactsAreCandidates() async {          // acceptance phrase 1
        let (p, _, _) = b.make(kind: "artifact", session: ["s-discovery": 0.72, "s-ideas": 0.26, "s-gif": 0.02])
        #expect(await p.pick(transcript: "for our next instagram reel video, open the artifact about discovery", cards: cards, context: b.idle)
            == .open(b.artifactTarget("fixture-discovery")))
        #expect(b.traces.last?.step == "jev")
        #expect(b.traces.last?.kind == "artifact")
    }

    @Test func aShownArtifactBeatsANewerReadOnlyOne() {
        #expect(cards.artifacts(of: "s-discovery").map(\.url.lastPathComponent) == ["fixture-discovery", "fixture-data"])
        #expect(cards.artifacts(of: "s-gif").map(\.url.lastPathComponent) == ["fixture-gif"])
        #expect(cards.artifacts(of: "s-ideas").isEmpty)
    }

    @Test func artifactTargetsAreNamedFromWhatIsKnown() {
        #expect(b.artifactTarget("fixture-gif") == Target(destination: .artifact(url: URL(string: Self.base + "fixture-gif")!),
                                                          title: "Reaction GIF Library", subtitle: "Chrome · artifact",
                                                          cardKey: "artifact:" + Self.base + "fixture-gif"))
        #expect(b.artifactTarget("fixture-discovery").title == "Artifact")
        var described = b.artifact("fixture-discovery")
        described.description = "A page that compares seven ways to find new reels today"
        #expect(cards.target(for: described).title == "A page that compares seven ways")
    }

    @Test func theGifArtifactOpens() async {                               // acceptance phrase 3
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.96, "s-ideas": 0.04])
        #expect(await p.pick(transcript: "open the artifact for the gif marking", cards: cards, context: b.idle) == .open(b.artifactTarget("fixture-gif")))
    }

    @Test func theArtifactQuestionChoosesWithinASession() async {
        let urls = (data: Self.base + "fixture-data", discovery: Self.base + "fixture-discovery", gif: Self.base + "fixture-gif")
        let (p, _, _) = b.make(kind: "artifact", session: ["s-discovery": 0.9, "s-gif": 0.1],
                               artifact: [urls.data: 0.35, urls.discovery: 0.15, urls.gif: 0.5])        // 0.7 of this session's share
        #expect(await p.pick(transcript: "open the data page from discovery", cards: cards, context: b.idle) == .open(b.artifactTarget("fixture-data")))
        let (q, _, _) = b.make(kind: "artifact", session: ["s-discovery": 0.9, "s-gif": 0.1],
                               artifact: [urls.data: 0.25, urls.discovery: 0.25, urls.gif: 0.5])        // 0.5: not clear enough
        #expect(await q.pick(transcript: "open the discovery page", cards: cards, context: b.idle) == .open(b.artifactTarget("fixture-discovery")))
    }

    @Test func anUnsureArtifactRequestOffersOnePagePerSession() async {
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.55, "s-discovery": 0.45])
        #expect(await p.pick(transcript: "open the review page from yesterday", cards: cards, context: b.idle)
            == .choices([b.artifactTarget("fixture-gif"), b.artifactTarget("fixture-discovery")], rememberable: true))
    }

    @Test func anArtifactRequestThatIsNotKnownMeansNothing() async {
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.5, "s-discovery": 0.5], known: 0.05)
        #expect(await p.pick(transcript: "open the artifact about my tax return", cards: cards, context: b.idle) == .nothing)
    }

    @Test func openTheArtifactUsesTheSessionInFront() async {             // acceptance phrase 6
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.5, "s-discovery": 0.5], describes: 0.1)
        #expect(await p.pick(transcript: "open the artifact", cards: cards, context: b.front("s-discovery")) == .open(b.artifactTarget("fixture-discovery")))
        #expect(b.traces.last?.step == "front")
    }

    @Test func aFrontSessionWithoutArtifactsDoesNotDecide() async {
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.9, "s-discovery": 0.1], describes: 0.1)
        #expect(await p.pick(transcript: "open the artifact", cards: cards, context: b.front("s-ideas")) == .open(b.artifactTarget("fixture-gif")))
    }

    @Test func aDescribedArtifactIgnoresWhatIsInFront() async {
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.95, "s-discovery": 0.05], describes: 0.9)
        #expect(await p.pick(transcript: "open the gif artifact", cards: cards, context: b.front("s-discovery")) == .open(b.artifactTarget("fixture-gif")))
    }

    @Test func openTheTerminalForThisUsesTheArtifactInFront() async {    // acceptance phrase 7
        let (p, _, _) = b.make(kind: "session", session: ["s-gif": 0.3, "s-ideas": 0.3], known: 0.1, describes: 0.1)
        #expect(await p.pick(transcript: "open the terminal for this", cards: cards, context: b.frontArtifact("fixture-gif")) == .open(b.target("s-gif")))
        #expect(b.traces.last?.step == "front")
    }

    @Test func twoRecentSessionsOnOneArtifactAreOffered() async throws {
        var both = b
        let index = try #require(both.cards.artifacts.firstIndex { $0.url.lastPathComponent == "fixture-gif" })
        let published = both.cards.artifacts[index].links[0].at
        both.cards.artifacts[index].links.append(ArtifactLink(sessionId: "s-share", shown: true, at: published.addingTimeInterval(300)))
        let (p, _, _) = both.make(kind: "session", session: ["s-gif": 0.3, "s-ideas": 0.3], describes: 0.1)
        #expect(await p.pick(transcript: "open the terminal for this", cards: both.cards, context: both.frontArtifact("fixture-gif"))
            == .choices([both.target("s-share"), both.target("s-gif")], rememberable: false))

        both.cards.artifacts[index].links[1].at = published.addingTimeInterval(3600)                     // clearly more recent
        #expect(await p.pick(transcript: "open the terminal for this", cards: both.cards, context: both.frontArtifact("fixture-gif"))
            == .open(both.target("s-share")))
        #expect(both.cards.openSessions(linkedTo: both.artifact("fixture-gif").url).map(\.session.id) == ["s-share", "s-gif"])
    }

    @Test func aDescribedSessionIgnoresTheArtifactInFront() async {
        let (p, _, _) = b.make(kind: "session", session: ["s-share": 0.95, "s-gif": 0.05], describes: 0.9)
        #expect(await p.pick(transcript: "open the open source session", cards: cards, context: b.frontArtifact("fixture-gif")) == .open(b.target("s-share")))
    }

    @Test func noArtifactsAnywhereMeansNothing() async {
        var bare = cards
        bare.artifacts = []
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.9])
        #expect(await p.pick(transcript: "open the gif artifact", cards: bare, context: b.idle) == .nothing)
        #expect(await p.pick(transcript: "open the artifact", cards: bare, context: b.front("s-gif")) == .nothing)
    }

    @Test func aRememberedArtifactOpensDirectly() async {
        let (p, jev, _) = b.make(remembered: ["open the gif page": "artifact:" + Self.base + "fixture-gif"])
        #expect(await p.pick(transcript: "Open the GIF page.", cards: cards, context: b.idle) == .open(b.artifactTarget("fixture-gif")))
        #expect(jev.calls == 0)
    }

    // Review finding 2: a phrase that does not say which thing is meant must never be remembered.
    @Test func anArtifactPhraseThatDoesNotSayWhichIsNotRememberable() async {
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.55, "s-discovery": 0.45], describes: 0.1)
        #expect(await p.pick(transcript: "open the artifact", cards: cards, context: b.idle)
            == .choices([b.artifactTarget("fixture-gif"), b.artifactTarget("fixture-discovery")], rememberable: false))
        // Even if Jev says the phrase describes something, a phrase with no word of its own is not remembered.
        let (q, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.55, "s-discovery": 0.45], describes: 0.9)
        #expect(await q.pick(transcript: "Open the artifact.", cards: cards, context: b.idle)
            == .choices([b.artifactTarget("fixture-gif"), b.artifactTarget("fixture-discovery")], rememberable: false))
    }

    @Test func aSessionPhraseThatDoesNotSayWhichIsNotRememberable() async {
        let (p, _, _) = b.make(kind: "session", session: ["s-gif": 0.4, "s-ideas": 0.35], describes: 0.1)
        #expect(await p.pick(transcript: "open the terminal for this", cards: cards, context: b.idle)
            == .choices([b.target("s-gif"), b.target("s-ideas")], rememberable: false))
    }

    @Test func aBarePhraseStoredEarlierDoesNotOverrideWhatIsInFront() async {
        let (p, _, store) = b.make(kind: "artifact", session: ["s-gif": 0.5, "s-discovery": 0.5], describes: 0.1,
                                   remembered: ["open the artifact": "artifact:" + Self.base + "fixture-gif"])
        #expect(await p.pick(transcript: "open the artifact", cards: cards, context: b.front("s-discovery"))
            == .open(b.artifactTarget("fixture-discovery")))                    // acceptance phrase 6
        #expect(store.cardKey(for: "open the artifact") == nil)                  // and the bad entry is dropped
    }

    // Review finding 3: the request is about a session that has no artifact. The little that is left for the
    // sessions that do have one must not be scaled up into a sure open.
    @Test func anArtifactOfASessionWithoutArtifactsOpensNothing() async {
        let (p, _, _) = b.make(kind: "artifact", session: ["s-chip": 0.92, "s-gif": 0.07, "s-discovery": 0.01], known: 0.9)
        #expect(await p.pick(transcript: "open the artifact for the chip design", cards: cards, context: b.idle) == .nothing)
        let (q, _, _) = b.make(kind: "artifact", session: ["s-front": 0.28, "s-discovery": 0.66, "s-ideas": 0.06])
        #expect(await q.pick(transcript: "for our next instagram reel video, open the artifact about discovery", cards: cards, context: b.idle)
            == .open(b.artifactTarget("fixture-discovery")))                    // the live answer for phrase 1 still opens
    }

    // Measured live on 2026-11-10: for acceptance phrase 1, Jev put 0.49 on the right session and 0.47 on the chat
    // session where the phrase had been discussed (which has no artifact). That is neither a clear "yes" nor a
    // request about something that is not a card: it is a question.
    @Test func aSplitAnswerForAnArtifactIsAskedNotOpenedAndNotDropped() async {
        let (p, _, _) = b.make(kind: "artifact", session: ["s-discovery": 0.49, "s-front": 0.47, "s-ideas": 0.04])
        #expect(await p.pick(transcript: "for our next instagram reel video, open the artifact about discovery", cards: cards, context: b.idle)
            == .choices([b.artifactTarget("fixture-discovery")], rememberable: true))
        let (q, _, _) = b.make(kind: "artifact", session: ["s-chip": 0.6, "s-gif": 0.25, "s-discovery": 0.15])
        #expect(await q.pick(transcript: "open the artifact for the chip design", cards: cards, context: b.idle)
            == .choices([b.artifactTarget("fixture-gif"), b.artifactTarget("fixture-discovery")], rememberable: true))
    }

    // The same answer, said from the chat session itself: that session is in front, has no artifact, and so cannot
    // be meant. Jev's second question (without it) decides.
    @Test func aFrontSessionWithoutArtifactsDoesNotDiluteAnArtifactRequest() async {
        let (p, _, _) = b.make(kind: "artifact", session: ["s-discovery": 0.49, "s-front": 0.47, "s-ideas": 0.04],
                               other: ["s-discovery": 0.93, "s-ideas": 0.07])
        #expect(await p.pick(transcript: "for our next instagram reel video, open the artifact about discovery", cards: cards, context: b.front("s-front"))
            == .open(b.artifactTarget("fixture-discovery")))
        // A front session that has an artifact of its own stays a candidate: the first question is used.
        let (q, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.9, "s-discovery": 0.1], other: ["s-discovery": 1.0])
        #expect(await q.pick(transcript: "open the gif review page", cards: cards, context: b.front("s-gif")) == .open(b.artifactTarget("fixture-gif")))
    }

    // From the third hand test: "open the pattern selection artifact" got a list although the page's title says
    // exactly that. When Jev's own question about pages is sure of a page that has a title, that page opens.
    @Test func aPageNamedByItsTitleOpensDirectly() async {
        let gif = Self.base + "fixture-gif", discovery = Self.base + "fixture-discovery"
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.6, "s-discovery": 0.4], artifact: [gif: 0.93, discovery: 0.07])
        #expect(await p.pick(transcript: "open the reaction gif library artifact", cards: cards, context: b.idle) == .open(b.artifactTarget("fixture-gif")))
        // A page without any text of its own cannot be "named": the session rule decides.
        let (q, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.6, "s-discovery": 0.4], artifact: [discovery: 0.93, gif: 0.07])
        #expect(await q.pick(transcript: "open the review page from yesterday", cards: cards, context: b.idle)
            == .choices([b.artifactTarget("fixture-gif"), b.artifactTarget("fixture-discovery")], rememberable: true))
        // And a page whose session Jev all but rules out is not opened on the page question alone.
        let (r, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.05, "s-discovery": 0.95], artifact: [gif: 0.93, discovery: 0.07])
        #expect(await r.pick(transcript: "open the discovery page", cards: cards, context: b.idle) == .open(b.artifactTarget("fixture-discovery")))
    }

    // When Jev does not answer in time, a request for an artifact is offered pages, not sessions.
    @Test func theFallbackOffersPagesForAnArtifactRequest() async {
        let (p, _, _) = b.make(error: .timeout)
        #expect(await p.pick(transcript: "open the reaction gif artifact", cards: cards, context: b.idle)
            == .choices([b.artifactTarget("fixture-gif")], rememberable: false))
        #expect(await p.pick(transcript: "open the gif library session", cards: cards, context: b.idle)
            == .choices([b.target("s-gif")], rememberable: false))
    }

    // From the fourth hand test: "open, patterns, artifact" opened the Jarvis mock-up. The session question pointed at
    // the chat in which artifacts are talked about (0.95); the page question pointed at the page with "Pattern" in its
    // title (0.65 against 0.30). Two answers that disagree are not a sure answer: both pages are offered, and the one
    // the page question prefers comes first.
    @Test func aPageAnswerThatDisagreesWithTheSessionAnswerIsOffered() async throws {
        var cards = b.cards
        let index = try #require(cards.artifacts.firstIndex { $0.url.lastPathComponent == "fixture-discovery" })
        cards.artifacts[index].title = "Discovery script"
        let gif = Self.base + "fixture-gif", discovery = Self.base + "fixture-discovery"
        let gifPage = cards.target(for: b.artifact("fixture-gif")), discoveryPage = cards.target(for: cards.artifacts[index])

        let (p, _, _) = b.make(kind: "artifact", session: ["s-discovery": 0.95, "s-gif": 0.05], artifact: [gif: 0.65, discovery: 0.30])
        #expect(await p.pick(transcript: "open the reactions artifact", cards: cards, context: b.idle)
            == .choices([gifPage, discoveryPage], rememberable: true))
        // A page the page question is sure of, in a session the session question all but rules out: the same.
        let (q, _, _) = b.make(kind: "artifact", session: ["s-discovery": 0.95, "s-gif": 0.05], artifact: [gif: 0.93, discovery: 0.07])
        #expect(await q.pick(transcript: "open the reactions artifact", cards: cards, context: b.idle)
            == .choices([gifPage, discoveryPage], rememberable: true))
        // When the page question has no clear favourite, the sure session answer decides as before.
        let (r, _, _) = b.make(kind: "artifact", session: ["s-discovery": 0.95, "s-gif": 0.05], artifact: [gif: 0.45, discovery: 0.40])
        #expect(await r.pick(transcript: "open the discovery artifact", cards: cards, context: b.idle) == .open(discoveryPage))
        // And when both questions agree, the page opens.
        let (t, _, _) = b.make(kind: "artifact", session: ["s-discovery": 0.95, "s-gif": 0.05], artifact: [gif: 0.2, discovery: 0.8])
        #expect(await t.pick(transcript: "open the discovery artifact", cards: cards, context: b.idle) == .open(discoveryPage))
    }
}
