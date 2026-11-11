import Foundation

/// Builds the one request sent to Jev for a spoken phrase. Everything that goes out passes through the scrubber here:
/// no paths, links, email addresses, long tokens or the user's name. Only card text is sent, never where a card lives.
public enum JevRequestBuilder {
    public struct Built {
        public var body: Data
        /// Option name → session id.
        public var sessionIds: [String: String]
        /// Option name → artifact link.
        public var artifactURLs: [String: String]
    }

    static let kindInstructions = "What does the speaker want brought up on screen?"
    static let kindCriteria = [
        "session": "A work session in a terminal: they say session, terminal or chat, or just name a piece of work",
        "artifact": "An artifact: a web page or review page that a work session produced",
        "app_or_website": "A named application or website, for example YouTube or ChatGPT",
    ]
    static let sessionInstructions = "Which open work session does the speaker want? Each option is named 'project folder / task'; "
        + "its description lists distinctive words the user typed there. The speaker usually names the project loosely "
        + "(for example 'the shop site' for a folder called shop-website) and adds a word or two about the task to tell "
        + "sessions in the same project apart. A lead-in such as 'for our next video' is background."
    static let artifactInstructions = "Which page is the spoken request about? Each option is a page that a work session produced or opened."
    static let knownInstructions = "Does `spoken_request` refer to one of `open_sessions`, or to an artifact that one of them produced?"
    static let describesInstructions = "Does `spoken_request` say which session or artifact is meant, by naming or describing it? "
        + "Answer no when it only says words like 'the artifact', 'this', 'its terminal' or 'the session for this'."

    public static func build(transcript: String, cards: CardSnapshot, front: FrontCard, scrubber: Scrubber) -> Built {
        // Sessions: unique, non-empty names of the form "folder / task".
        var sessionNames: [(name: String, card: SessionCard)] = []
        var used = Set<String>()
        for card in cards.sessions {
            let folder = nonEmpty(scrubber.scrub(card.folderLabel)) ?? "folder"
            let task = nonEmpty(scrubber.scrub(card.label)) ?? SessionReader.untitled
            sessionNames.append((unique("\(folder) / \(task)", in: &used), card))
        }
        func sessionCriteria(_ list: [(name: String, card: SessionCard)]) -> [String: Any] {
            var criteria: [String: Any] = [:]
            for (name, card) in list {
                let words = card.gist.compactMap { nonEmpty(scrubber.scrub($0)) }
                let pages = cards.artifacts(of: card.id).compactMap { $0.title }.compactMap { nonEmpty(scrubber.scrub($0)) }
                let replies = card.replyGist.compactMap { nonEmpty(scrubber.scrub($0)) }
                let parts = [words.isEmpty ? nil : "Distinctive words the user typed in this session: \(words.joined(separator: ", ")).",
                             replies.isEmpty ? nil : "Distinctive words in what Claude wrote there: \(replies.joined(separator: ", ")).",
                             pages.isEmpty ? nil : "Pages it produced or opened: \(pages.joined(separator: "; "))."].compactMap { $0 }
                criteria[name] = parts.isEmpty ? NSNull() : parts.joined(separator: " ")
            }
            return criteria
        }

        var questions: [String: Any] = [
            "kind": ["type": "choice", "instructions": kindInstructions, "criteria": kindCriteria],
            "known": ["type": "noul", "instructions": knownInstructions],
            "describes": ["type": "noul", "instructions": describesInstructions],
        ]
        if !sessionNames.isEmpty {
            questions["session_all"] = ["type": "choice", "instructions": sessionInstructions, "criteria": sessionCriteria(sessionNames)]
        }
        if case .session(let frontId) = front, sessionNames.contains(where: { $0.card.id == frontId }) {
            let others = sessionNames.filter { $0.card.id != frontId }
            if others.count > 1 {
                questions["session_other"] = ["type": "choice", "instructions": sessionInstructions, "criteria": sessionCriteria(others)]
            }
        }

        // Artifacts: named by title, else the first words of the description, else a placeholder.
        var artifactURLs: [String: String] = [:]
        var artifactCriteria: [String: Any] = [:]
        var usedPages = Set<String>()
        let labels = Dictionary(cards.sessions.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        for card in cards.artifacts {
            let description = card.description.flatMap { nonEmpty(scrubber.scrub($0)) }
            let title = card.title.flatMap { nonEmpty(scrubber.scrub($0)) }
            let firstWords = description.map { $0.split(separator: " ").prefix(6).joined(separator: " ") }
            let name = unique(title ?? firstWords ?? "untitled page", in: &usedPages)
            let newest = card.links.filter { labels[$0.sessionId] != nil }.max { $0.at < $1.at }
            let from = newest.flatMap { labels[$0.sessionId] }.flatMap { nonEmpty(scrubber.scrub($0)) }.map { "From session: \($0)." }
            let text = [description, from].compactMap { $0 }.joined(separator: " ")
            artifactURLs[name] = card.url.absoluteString
            artifactCriteria[name] = text.isEmpty ? NSNull() : text
        }
        if !artifactCriteria.isEmpty {
            questions["artifact"] = ["type": "choice", "instructions": artifactInstructions, "criteria": artifactCriteria]
        }

        // The sessions are listed with what is known about them, so that the yes/no questions (which see only this
        // list) can tell that "the Jarvis session" is one of them even when no session is called that.
        let described = sessionCriteria(sessionNames)
        let listed: [[String: Any]] = sessionNames.map { ["name": $0.name, "about": described[$0.name] ?? NSNull()] }
        let body: [String: Any] = [
            "model": "jev-latest",
            "state": ["spoken_request": scrubber.scrub(transcript), "open_sessions": listed],
            "questions": questions,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return Built(body: data, sessionIds: Dictionary(uniqueKeysWithValues: sessionNames.map { ($0.name, $0.card.id) }), artifactURLs: artifactURLs)
    }

    private static func nonEmpty(_ s: String) -> String? {
        s.isEmpty ? nil : s
    }

    /// The name itself the first time, then "name (2)", "name (3)" and so on.
    private static func unique(_ name: String, in used: inout Set<String>) -> String {
        var candidate = name
        var number = 2
        while !used.insert(candidate).inserted {
            candidate = "\(name) (\(number))"
            number += 1
        }
        return candidate
    }
}
