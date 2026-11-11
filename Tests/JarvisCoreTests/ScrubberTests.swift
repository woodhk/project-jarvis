import Foundation
import Testing
@testable import JarvisCore

@Suite struct ScrubberTests {
    let s = Scrubber(userNames: ["sam", "rivera"])

    @Test func privateThingsAreRemoved() {
        #expect(s.scrub("see https://x.test/a?b=1 and mail sam@x.test about /Users/sam/secret.txt") == "see and mail about")
        #expect(s.scrub("key sk9aB3xQ72LmNo04PqRs77 ok") == "key ok")
        #expect(s.scrub("Sam's plan, by Rivera") == "'s plan, by")
        #expect(s.scrub("samples are fine") == "samples are fine")
    }

    @Test func ordinaryTextIsLeftAlone() {
        #expect(s.scrub("insta-comment-dm / Shareable repo setup guide") == "insta-comment-dm / Shareable repo setup guide")
        #expect(s.scrub("Review 164 reaction GIFs one at a time") == "Review 164 reaction GIFs one at a time")
        #expect(s.scrub("internationalization is one long word") == "internationalization is one long word")
        #expect(s.scrub("session 5dafb92e-1ae4-46f8-a784-3baddc0a277d ended") == "session ended")
        #expect(s.scrub("") == "")
    }

    // Review finding 11: a name joined to another word (folder names often are) must go too.
    @Test func aNameJoinedToAnotherWordIsRemoved() {
        #expect(s.scrub("sam_videos") == "_videos")
        #expect(s.scrub("SamNotes and rivera-site") == "Notes and -site")
        #expect(s.scrub("videos_sam") == "videos_")
        #expect(s.scrub("samples and samba are fine") == "samples and samba are fine")
    }

    @Test func theSystemNamesAreUsableWords() {
        let names = Scrubber.systemUserNames()
        #expect(!names.isEmpty)
        #expect(names.allSatisfy { $0.count >= 3 && $0 == $0.lowercased() })
    }
}

@Suite struct GistBuilderTests {
    let history = CoreFixture.claude.appendingPathComponent("history.jsonl")

    @Test func theTellingWordsOfASessionLeadItsGist() throws {
        let g = GistBuilder(userNames: ["sam"]).gists(historyFile: history, for: ["A", "B"])
        let a = try #require(g["A"]), b = try #require(g["B"])
        #expect(a.prefix(3).contains("open source"))
        #expect(!b.contains("open source"))
        #expect(a.count <= 12)
        #expect(b.first == "door")
        #expect(g["C"] == nil)                         // not asked for
    }

    @Test func linksPathsAndNamesNeverReachAGist() throws {
        let all = try #require(GistBuilder(userNames: ["sam"]).gists(historyFile: history, for: ["A"])["A"]).joined(separator: " ")
        #expect(!all.contains("http"))
        #expect(!all.contains("example"))
        #expect(!all.contains("users"))
        #expect(!all.contains("sam"))
        #expect(all.contains("license"))
    }

    @Test func aTermInsideOneAlreadyTakenIsSkipped() throws {
        let a = try #require(GistBuilder(userNames: []).gists(historyFile: history, for: ["A"])["A"])
        #expect(a.contains("open source"))
        #expect(!a.contains("open"))
        #expect(!a.contains("source"))
    }

    @Test func theLimitAndUnknownSessionsAreRespected() {
        let builder = GistBuilder(userNames: [])
        #expect(builder.gists(historyFile: history, for: ["A"], top: 2)["A"]?.count == 2)
        #expect(builder.gists(historyFile: history, for: ["nobody"])["nobody"] == nil)
        #expect(builder.gists(historyFile: CoreFixture.claude.appendingPathComponent("no-such-file.jsonl"), for: ["A"]).isEmpty)
    }
}
