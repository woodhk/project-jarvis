import Foundation

/// Builds the gist of each session: the most distinctive words and word pairs the user typed there,
/// scored against every other session (term frequency times inverse document frequency). No model is involved.
public struct GistBuilder: Sendable {
    static let stopwords: Set<String> = Set("""
    the and for that this with you your have not but can are was will what when how from they them then than there here \
    just like want need make made let lets get got also into out about its it's i'm i've don't doesn't didn't can't should \
    would could does did has had been being one two all any some more most other our their his her she him who why where \
    which while were use used using yes yeah yea okay sure please thanks thank now still very much many way see look go \
    going back again new old add added run running file files thing things something anything lot bit actually really \
    maybe think know well good great right first last next each per via too only same over under after before both \
    between because
    """.split(separator: " ").map(String.init))

    private let scrubber: Scrubber
    private let userNames: [String]

    public init(userNames: [String]) {
        self.userNames = userNames.map { $0.lowercased() }.filter { !$0.isEmpty }
        scrubber = Scrubber(userNames: userNames)
    }

    /// The gist of each requested session that has typed prompts in `historyFile` (Claude Code's history.jsonl).
    public func gists(historyFile: URL, for sessionIds: Set<String>, top: Int = 12) -> [String: [String]] {
        guard let data = try? Data(contentsOf: historyFile, options: .mappedIfSafe) else { return [:] }
        var counts: [String: [String: Int]] = [:]            // only for the sessions asked for
        var seenBy: [String: Set<String>] = [:]              // term → sessions that used it (for the document frequency)
        var sessions = Set<String>()
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let session = record["sessionId"] as? String, let text = record["display"] as? String, !text.isEmpty else { continue }
            sessions.insert(session)
            let wanted = sessionIds.contains(session)
            for term in terms(in: text) {
                seenBy[term, default: []].insert(session)
                if wanted { counts[session, default: [:]][term, default: 0] += 1 }
            }
        }
        let total = Double(sessions.count)
        var result: [String: [String]] = [:]
        for (session, termCounts) in counts {
            let keepAll = termCounts.count < 40
            let scored = termCounts.filter { keepAll || $0.value >= 2 }.map { term, count in
                (term: term, count: count, score: Double(count) * log(total / Double(seenBy[term]?.count ?? 1)))
            }.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.term.count != $1.term.count { return $0.term.count > $1.term.count }
                return $0.term < $1.term
            }
            var taken: [String] = []
            for candidate in scored {
                if taken.count == top { break }
                if taken.contains(where: { $0.contains(candidate.term) || candidate.term.contains($0) }) { continue }
                taken.append(candidate.term)
            }
            result[session] = taken
        }
        return result
    }

    /// The distinct words and adjacent word pairs of one prompt, after the privacy scrub.
    func terms(in prompt: String) -> Set<String> {
        let words = Self.words(in: scrubber.scrub(prompt.lowercased(), removingNames: false)).filter { word in
            !Self.stopwords.contains(word) && !userNames.contains { word.contains($0) }
        }
        var terms = Set(words)
        for (first, second) in zip(words, words.dropFirst()) { terms.insert(first + " " + second) }
        return terms
    }

    /// Runs of 3 to 15 characters that start with a letter and continue with letters, apostrophes or hyphens.
    static func words(in text: String) -> [String] {
        var words: [String] = []
        let bytes = Array(text.utf8)
        var i = 0
        func isLetter(_ b: UInt8) -> Bool { b >= 0x61 && b <= 0x7A }
        while i < bytes.count {
            guard isLetter(bytes[i]) else { i += 1; continue }
            var j = i + 1
            while j < bytes.count, j - i < 15, isLetter(bytes[j]) || bytes[j] == 0x27 || bytes[j] == 0x2D { j += 1 }
            if j - i >= 3 {
                words.append(String(decoding: bytes[i..<j], as: UTF8.self))
                i = j
            } else {
                i += 1
            }
        }
        return words
    }
}
