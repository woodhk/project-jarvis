import Foundation

/// Builds, for each open session, the most distinctive words of Claude's replies in it: what the session is about,
/// even when the user never typed it (the topic may be in a brief file and in the answers).
///
/// What counts is what Claude wrote: its replies, and the documents it wrote in the session (a Claude Doc it
/// edited, text files it saved, artifact descriptions). Tool results (files it read), shell commands, code files,
/// helper agents' messages and the stored request blobs are skipped, and code blocks are removed. The same privacy scrub as for typed prompts
/// applies. History files are large and grow all the time, so each file is read only from where the last read ended.
public final class ReplyGistBuilder: @unchecked Sendable {
    private struct Entry {
        var offset = 0
        var counts: [String: Int] = [:]
    }

    private static let assistantMark = Array("\"type\":\"assistant\"".utf8)
    private static let requestBlob = Array("\"type\":\"api-request".utf8)
    private static let codeBlock = try! NSRegularExpression(pattern: "```[\\s\\S]*?```")
    /// Words Claude uses everywhere; they say nothing about a session.
    private static let fillers: Set<String> = ["i'll", "here's", "that's", "let's", "there's", "what's", "you're", "we're", "isn't", "won't",
                                               "wasn't", "aren't", "i'd", "you'd", "you'll", "we'll", "they're", "done", "ready"]

    private let builder: GistBuilder
    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var read = 0

    public init(userNames: [String]) {
        builder = GistBuilder(userNames: userNames)
    }

    /// How many bytes of history have been read so far (for measuring).
    public var bytesRead: Int { lock.withLock { read } }

    /// Session id → up to `top` terms, for each session whose history file holds replies.
    /// A term scores by how many replies use it, and less the more of these sessions use it too.
    public func gists(historyFiles: [String: URL], top: Int = 20) -> [String: [String]] {
        lock.lock()
        defer { lock.unlock() }
        var counts: [String: [String: Int]] = [:]
        for (session, file) in historyFiles {
            let found = update(file)
            if !found.isEmpty { counts[session] = found }
        }
        var usedBy: [String: Int] = [:]
        for terms in counts.values {
            for term in terms.keys { usedBy[term, default: 0] += 1 }
        }
        let sessions = counts.count
        var result: [String: [String]] = [:]
        for (session, terms) in counts {
            let minimum = terms.count < 40 ? 1 : (terms.count < 400 ? 2 : 3)
            let scored = terms.filter { $0.value >= minimum }.compactMap { term, count -> (term: String, count: Int, score: Double)? in
                let users = usedBy[term] ?? 1
                if sessions >= 3, users == sessions { return nil }          // every open session says it
                return (term, count, Double(count) * log(Double(sessions + 1) / Double(users)))
            }.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.term.count != $1.term.count { return $0.term.count > $1.term.count }
                return $0.term < $1.term
            }
            // Half of the gist is the most distinctive terms, the other half the most used ones. A session's topic
            // words are often said in other sessions too; by distinctiveness alone they lose to rare phrases.
            var taken: [String] = []
            func take(from list: [(term: String, count: Int, score: Double)], upTo limit: Int) {
                for candidate in list {
                    if taken.count >= limit { break }
                    if taken.contains(where: { $0.contains(candidate.term) || candidate.term.contains($0) }) { continue }
                    taken.append(candidate.term)
                }
            }
            take(from: scored, upTo: (top + 1) / 2)
            take(from: scored.sorted { ($0.count, $0.score) > ($1.count, $1.score) }, upTo: top)
            if !taken.isEmpty { result[session] = taken }
        }
        return result
    }

    private static let proseFiles: Set<String> = ["md", "markdown", "mdx", "txt", "rst"]

    /// The prose Claude wrote through a tool: the new text of a Markdown or text file, what it put into a Claude Doc,
    /// the title and description it gave an artifact. Code files and every other tool are left out.
    static func written(tool: String, input: [String: Any]) -> [String] {
        func isProse(_ path: Any?) -> Bool {
            guard let path = path as? String else { return false }
            return proseFiles.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        }
        /// Every string inside a value that reads like prose (it has a space); identifiers and addresses do not.
        func prose(in value: Any) -> [String] {
            if let text = value as? String { return text.contains(" ") ? [text] : [] }
            if let list = value as? [Any] { return list.flatMap(prose(in:)) }
            if let map = value as? [String: Any] { return map.values.flatMap(prose(in:)) }
            return []
        }
        switch tool {
        case "Write":
            return isProse(input["file_path"]) ? prose(in: input["content"] ?? "") : []
        case "Edit":
            return isProse(input["file_path"]) ? prose(in: input["new_string"] ?? "") : []
        case "MultiEdit":
            guard isProse(input["file_path"]) else { return [] }
            return (input["edits"] as? [[String: Any]] ?? []).flatMap { prose(in: $0["new_string"] ?? "") }
        case "Artifact":
            return prose(in: [input["title"] ?? "", input["description"] ?? ""])
        default:
            return tool.contains("Docs__") ? prose(in: input) : []
        }
    }

    /// Reads what was added to the file since the last call and returns the counts for the whole file so far.
    private func update(_ file: URL) -> [String: Int] {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [:] }
        var entry = cache[file.path] ?? Entry()
        if data.count < entry.offset { entry = Entry() }                    // the file was replaced
        guard data.count > entry.offset else { return entry.counts }
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else { return }
            let count = bytes.count
            read += count - entry.offset
            var start = entry.offset
            // Only whole lines are taken: the last line may still be being written.
            while start < count, let newline = memchr(base + start, 0x0A, count - start) {
                let end = base.distance(to: UnsafeRawPointer(newline))
                let line = base + start
                let length = end - start
                start = end + 1
                entry.offset = start
                guard memmem(line, min(length, 60), Self.requestBlob, Self.requestBlob.count) == nil,
                      memmem(line, length, Self.assistantMark, Self.assistantMark.count) != nil,
                      let record = try? JSONSerialization.jsonObject(with: Data(bytes: line, count: length)) as? [String: Any],
                      record["type"] as? String == "assistant", record["isSidechain"] as? Bool != true,
                      let message = record["message"] as? [String: Any] else { continue }
                var texts: [String] = []
                if let text = message["content"] as? String { texts.append(text) }
                for block in message["content"] as? [[String: Any]] ?? [] {
                    switch block["type"] as? String {
                    case "text":
                        if let text = block["text"] as? String { texts.append(text) }
                    case "tool_use":
                        texts += Self.written(tool: block["name"] as? String ?? "", input: block["input"] as? [String: Any] ?? [:])
                    default:
                        break
                    }
                }
                for text in texts {
                    let prose = Self.codeBlock.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
                    for term in builder.terms(in: prose) where !Self.fillers.contains(term) {
                        entry.counts[term, default: 0] += 1
                    }
                }
            }
        }
        cache[file.path] = entry
        return entry.counts
    }
}
