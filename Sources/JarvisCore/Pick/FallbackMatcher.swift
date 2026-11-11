import Foundation

/// A plain word match over session cards, for when Jev does not answer. Its results are only ever offered, never opened.
public enum FallbackMatcher {
    private static let ignored: Set<String> = ["session", "terminal", "artifact", "it", "page", "tab", "window", "chat"]

    /// The words of a phrase that say something about what is wanted: what is left after the lead-in ("open the"),
    /// everyday words, and words such as "session" or "artifact" that only name the kind of thing.
    /// "Open the artifact" and "open the terminal for this" have none.
    public static func contentWords(_ transcript: String) -> [String] {
        Normalizer.words(Normalizer.stripLead(transcript)).filter { !GistBuilder.stopwords.contains($0) && !ignored.contains($0) }
    }

    /// Session cards that share at least one word with the phrase, best first. Equal scores keep the order of the cards.
    public static func rank(_ transcript: String, cards: CardSnapshot) -> [Target] {
        let spoken = contentWords(transcript)
        guard !spoken.isEmpty else { return [] }
        let scored = cards.sessions.enumerated().compactMap { index, card -> (score: Int, index: Int, card: SessionCard)? in
            let cardWords = Set(Normalizer.words(card.label) + Normalizer.words(card.folderLabel)
                + card.gist.flatMap(Normalizer.words) + card.replyGist.flatMap(Normalizer.words))
            let score = spoken.filter { word in
                cardWords.contains(word) || (word.count >= 4 && cardWords.contains { $0.hasPrefix(word) })
            }.count
            return score > 0 ? (score, index, card) : nil
        }
        return scored.sorted { ($0.score, $1.index) > ($1.score, $0.index) }.map { cards.target(for: $0.card) }
    }

    /// True when the phrase asks for an artifact or a page, not a session.
    public static func asksForPage(_ transcript: String) -> Bool {
        let words = Normalizer.words(transcript)
        return words.contains("artifact") || words.contains("page")
    }

    /// Artifact cards that share at least one word with the phrase, best first. A page is known by its title, its
    /// description, and the sessions it belongs to.
    public static func rankPages(_ transcript: String, cards: CardSnapshot) -> [Target] {
        let spoken = contentWords(transcript)
        guard !spoken.isEmpty else { return [] }
        let scored = cards.artifacts.enumerated().compactMap { index, card -> (score: Int, index: Int, card: ArtifactCard)? in
            let owners = cards.sessions.filter { session in card.links.contains { $0.sessionId == session.id } }
            let cardWords = Set(Normalizer.words(card.title ?? "") + Normalizer.words(card.description ?? "")
                + owners.flatMap { Normalizer.words($0.label) + Normalizer.words($0.folderLabel) })
            let score = spoken.filter { word in
                cardWords.contains(word) || (word.count >= 4 && cardWords.contains { $0.hasPrefix(word) })
            }.count
            return score > 0 ? (score, index, card) : nil
        }
        return scored.sorted { ($0.score, $1.index) > ($1.score, $0.index) }.map { cards.target(for: $0.card) }
    }
}
