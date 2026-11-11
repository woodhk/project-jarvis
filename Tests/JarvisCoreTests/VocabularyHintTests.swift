import Foundation
import Testing
@testable import JarvisCore

@Suite struct VocabularyHintTests {
    let cards: CardSnapshot

    init() throws { cards = try CoreFixture.cards() }

    @Test func theHintSpeaksFolderNames() {
        let h = cards.vocabularyHint(extraWords: ["Notes"])
        #expect(h.hasPrefix("Claude Code session, artifact, terminal, "))
        #expect(h.contains("insta comment dm"))
        #expect(!h.contains("insta-comment-dm"))
        #expect(!h.contains("_"))
        #expect(h.contains("open source"))
        #expect(h.contains("Reaction GIF Library"))
        #expect(h.contains("YouTube"))
        #expect(h.hasSuffix("Notes"))
    }

    @Test func theHintIsCappedAndHasNoRepeats() {
        let h = cards.vocabularyHint(maxChars: 80)
        #expect(h.count <= 80)
        #expect(!h.hasSuffix(","))
        #expect(!h.hasSuffix(" "))
        #expect(cards.vocabularyHint().components(separatedBy: "stream audio converter").count == 2)
        #expect(cards.vocabularyHint(extraWords: ["youtube", "Terminal"]).components(separatedBy: ", ").filter { $0.lowercased() == "youtube" }.count == 1)
        #expect(CardSnapshot().vocabularyHint() == "Claude Code session, artifact, terminal")
    }

    @Test func onlyTheFirstThreeGistTermsOfEachSessionAreUsed() {
        let h = cards.vocabularyHint()
        #expect(h.contains("github"))                 // third term of s-share
        #expect(!h.contains("saw reel"))              // fifth term of s-share
    }
}
