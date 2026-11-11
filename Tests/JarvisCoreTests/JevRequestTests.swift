import Foundation
import Testing
@testable import JarvisCore

extension CoreFixture {
    /// The cards behind the acceptance phrases: six sessions, three artifacts, two websites and one app.
    static func cards(_ name: String = "acceptance-cards") throws -> CardSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CardSnapshot.self, from: Data(contentsOf: dir.appendingPathComponent("\(name).json")))
    }
}

func json(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func questions(_ built: JevRequestBuilder.Built) throws -> [String: Any] {
    try #require(try json(built.body)["questions"] as? [String: Any])
}

/// Option name → description (nil for a null description) of one choice question. Empty when the question is absent.
func criteria(_ questions: [String: Any], _ name: String) -> [String: String?] {
    let raw = (questions[name] as? [String: Any])?["criteria"] as? [String: Any] ?? [:]
    return raw.mapValues { $0 as? String }
}

@Suite struct JevRequestTests {
    let cards: CardSnapshot
    let scrub = Scrubber(userNames: ["sam"])

    init() throws { cards = try CoreFixture.cards() }

    @Test func optionsAreNamedFolderSlashTask() throws {
        let b = JevRequestBuilder.build(transcript: "x", cards: cards, front: .none, scrubber: scrub)
        #expect(b.sessionIds["insta-comment-dm / Shareable repo setup guide"] == "s-share")
        #expect(b.sessionIds["home / Computer vision Mac cursor control"] == "s-front")
        let q = try questions(b)
        #expect(q["session_other"] == nil)
        #expect(try json(b.body)["model"] as? String == "jev-latest")
        #expect(criteria(q, "session_all")["insta-comment-dm / Shareable repo setup guide"]
            == "Distinctive words the user typed in this session: open source, coffee, github, bot, saw reel, reel comment-to-dm.")
    }

    @Test func theRequestHasTheAgreedShape() throws {
        let b = JevRequestBuilder.build(transcript: "open the gif session", cards: cards, front: .none, scrubber: scrub)
        let body = try json(b.body)
        let state = try #require(body["state"] as? [String: Any])
        #expect(state["spoken_request"] as? String == "open the gif session")
        // Each session is listed with what is known about it, so the yes/no questions can use it too.
        let listed = try #require(state["open_sessions"] as? [[String: Any]])
        #expect(Set(listed.compactMap { $0["name"] as? String }) == Set(b.sessionIds.keys))
        #expect(listed.first { $0["name"] as? String == "insta-comment-dm / Shareable repo setup guide" }?["about"] as? String
            == "Distinctive words the user typed in this session: open source, coffee, github, bot, saw reel, reel comment-to-dm.")
        let q = try questions(b)
        #expect(Set(q.keys) == ["kind", "session_all", "artifact", "known", "describes"])
        #expect((q["kind"] as? [String: Any])?["type"] as? String == "choice")
        #expect((q["kind"] as? [String: Any])?["instructions"] as? String == "What does the speaker want brought up on screen?")
        #expect(Set(criteria(q, "kind").keys) == ["session", "artifact", "app_or_website"])
        #expect((q["known"] as? [String: Any])?["type"] as? String == "noul")
        #expect(((q["describes"] as? [String: Any])?["instructions"] as? String)?.hasPrefix("Does `spoken_request` say which session or artifact is meant") == true)
    }

    @Test func theFrontSessionIsLeftOutOfTheSecondQuestion() throws {
        let b = JevRequestBuilder.build(transcript: "x", cards: cards, front: .session(id: "s-front"), scrubber: scrub)
        #expect(criteria(try questions(b), "session_other").count == 5)
        #expect(criteria(try questions(b), "session_all").count == 6)
        #expect(criteria(try questions(b), "session_other")["home / Computer vision Mac cursor control"] == nil)
    }

    @Test func theSecondQuestionIsOmittedWhenOnlyOneSessionWouldRemain() throws {
        var two = cards
        two.sessions = Array(cards.sessions.prefix(2))
        let b = JevRequestBuilder.build(transcript: "x", cards: two, front: .session(id: "s-ideas"), scrubber: scrub)
        #expect(try questions(b)["session_other"] == nil)
    }

    @Test func duplicateAndEmptyNamesAreMadeUnique() throws {
        var twins = CardSnapshot()
        for id in ["a", "b", "c"] {
            twins.sessions.append(SessionCard(id: id, pid: 1, shellPid: 2, tty: "/dev/ttys001", host: .terminal, folderPath: "/work/shop",
                                              folderLabel: "shop", label: id == "c" ? "Sam" : "untitled session", gist: []))
        }
        let b = JevRequestBuilder.build(transcript: "x", cards: twins, front: .none, scrubber: scrub)
        #expect(b.sessionIds == ["shop / untitled session": "a", "shop / untitled session (2)": "b", "shop / untitled session (3)": "c"])
        let described = criteria(try questions(b), "session_all")
        #expect(described.count == 3)
        #expect(described.values.allSatisfy { $0 == nil })          // an empty gist gives a null description
    }

    @Test func nothingPrivateIsInTheBody() throws {
        var risky = cards
        risky.sessions[0].label = "Sam's plan"
        risky.sessions[0].gist = ["sam@x.test", "https://x.test/a", "/Users/sam/notes", "sk9aB3xQ72LmNo04PqRs77", "reel"]
        risky.artifacts[0].title = "Sam's review page"
        risky.artifacts[0].description = "See https://x.test/page and /Users/sam/secret.txt for sam@x.test"
        let b = JevRequestBuilder.build(transcript: "Sam says open /Users/sam/x from https://x.test", cards: risky, front: .session(id: "s-front"), scrubber: scrub)
        let body = String(decoding: b.body, as: UTF8.self)
        for banned in ["http", "/Users", "x.test", "sk9aB3xQ72LmNo04PqRs77", "/work/", "/dev/tty", "claude.ai"] {
            #expect(!body.contains(banned), "the request body contains \(banned)")
        }
        // The name as a word of its own, in any letter case. (The fixed instructions contain the word "same".)
        #expect(body.range(of: #"\bsam\b"#, options: [.regularExpression, .caseInsensitive]) == nil)
    }

    @Test func anArtifactWithoutTextStillGetsAName() throws {
        let b = JevRequestBuilder.build(transcript: "x", cards: cards, front: .none, scrubber: scrub)
        #expect(b.artifactURLs["untitled page"] != nil)
        #expect(b.artifactURLs["untitled page (2)"] != nil)
        #expect(b.artifactURLs["Reaction GIF Library"] == "https://claude.ai/artifact/fixture-gif")
        let described = criteria(try questions(b), "artifact")
        #expect(described["Reaction GIF Library"] == "Review 164 reaction GIFs one at a time: approve with the moments each is for, or reject. From session: Emotion-tagged GIF library.")
        #expect(described[try #require(b.artifactURLs.first { $0.value.hasSuffix("fixture-discovery") }?.key)] == "From session: discovery-reel.")
    }

    @Test func withNoArtifactsOrSessionsThoseQuestionsAreOmitted() throws {
        let bare = CardSnapshot(apps: cards.apps, sites: cards.sites)
        let q = try questions(JevRequestBuilder.build(transcript: "x", cards: bare, front: .none, scrubber: scrub))
        #expect(Set(q.keys) == ["kind", "known", "describes"])
    }

    // From the first hand test: nothing Jarvis knew about a session said what its page was about.
    // The titles of a session's own pages now describe the session too.
    @Test func aSessionIsAlsoDescribedByItsPages() throws {
        var titled = cards
        let index = try #require(titled.artifacts.firstIndex { $0.url.lastPathComponent == "fixture-discovery" })
        titled.artifacts[index].title = "Pattern selection script"
        let described = criteria(try questions(JevRequestBuilder.build(transcript: "x", cards: titled, front: .none, scrubber: scrub)), "session_all")
        #expect(described["stream_audio_converter / Emotion-tagged GIF library"]
            == "Distinctive words the user typed in this session: gifs, emotion, wtf gif, videos paired, typing gif. Pages it produced or opened: Reaction GIF Library.")
        #expect(described["stream_audio_converter / discovery-reel"]??.hasSuffix("Pages it produced or opened: Pattern selection script.") == true)
        var silent = titled
        silent.sessions = silent.sessions.map { var s = $0; s.gist = []; return s }
        let bare = criteria(try questions(JevRequestBuilder.build(transcript: "x", cards: silent, front: .none, scrubber: scrub)), "session_all")
        #expect(bare["stream_audio_converter / discovery-reel"] == "Pages it produced or opened: Pattern selection script.")
        #expect(bare["insta-comment-dm / Shareable repo setup guide"] == .some(nil))
    }

    // A page that is open in Chrome shows its title there, even when the session only opened it and never named it.
    @Test func anUntitledPageTakesTheTitleOfItsChromeTab() throws {
        let tabs = [(url: "https://www.youtube.com/watch?v=1", title: "A video - YouTube"),
                    (url: "https://claude.ai/artifact/fixture-discovery?x=1", title: "Tool #5: pattern selection script | Claude"),
                    (url: "https://claude.ai/artifact/fixture-gif", title: "Something else - Claude"),
                    (url: "https://claude.ai/artifact/fixture-data", title: "Claude")]
        let titled = cards.takingTitles(fromTabs: tabs)
        #expect(titled.artifacts.first { $0.url.lastPathComponent == "fixture-discovery" }?.title == "Tool #5: pattern selection script")
        #expect(titled.artifacts.first { $0.url.lastPathComponent == "fixture-gif" }?.title == "Reaction GIF Library")      // its own title is kept
        #expect(titled.artifacts.first { $0.url.lastPathComponent == "fixture-data" }?.title == nil)                          // "Claude" alone says nothing
        #expect(titled.vocabularyHint().contains("pattern selection script"))
    }

    // The user allowed this on 2026-11-11: distinctive words from Claude's replies describe a session too.
    @Test func aSessionIsAlsoDescribedByClaudesReplies() throws {
        var told = cards
        let index = try #require(told.sessions.firstIndex { $0.id == "s-discovery" })
        told.sessions[index].replyGist = ["augmented llm", "workflows", "Sam's agents", "https://x.test/a"]
        let b = JevRequestBuilder.build(transcript: "x", cards: told, front: .none, scrubber: scrub)
        #expect(criteria(try questions(b), "session_all")["stream_audio_converter / discovery-reel"]
            == "Distinctive words the user typed in this session: concrete examples, seamless, window shows, type reel, tutorial shows. "
             + "Distinctive words in what Claude wrote there: augmented llm, workflows, 's agents.")
        #expect(told.vocabularyHint().contains("augmented llm"))
        #expect(FallbackMatcher.rank("open the workflows thing", cards: told).first?.cardKey == "session:s-discovery")
        #expect(try CoreFixture.cards().sessions.allSatisfy { $0.replyGist.isEmpty })      // older card files without the field still load
    }
}
