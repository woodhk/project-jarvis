import Foundation

/// One thing a session did with an artifact: published it, opened it, or read it.
public struct ArtifactEvent: Equatable, Sendable, Codable {
    public var url: URL
    public var sessionId: String
    /// True for a publish or an open; false when the session only read the page.
    public var shown: Bool
    public var title: String?
    public var description: String?
    public var filePath: String?
    public var at: Date
}

/// Finds artifact events in a session's history file. Only calls of the `Artifact` tool count:
/// many other records mention artifact links (pasted text, system text) and are ignored.
public enum ArtifactScanner {
    static let link = try! NSRegularExpression(pattern: #"https://claude\.ai/(?:code/)?artifact/[A-Za-z0-9-]+"#)
    private static let toolName = Array("\"Artifact\"".utf8)
    private static let linkPart = Array("artifact/".utf8)
    private static let requestBlob = Array("\"type\":\"api-request".utf8)

    private struct Call {
        var input: [String: Any]
        var at: Date
    }

    public static func events(in historyFile: URL, sessionId: String) -> [ArtifactEvent] {
        guard let data = try? Data(contentsOf: historyFile, options: .mappedIfSafe), !data.isEmpty else { return [] }
        var pending: [String: Call] = [:]            // tool-use id → the call waiting for its result
        var events: [ArtifactEvent] = []
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else { return }
            let count = bytes.count
            var start = 0
            while start < count {
                let end = memchr(base + start, 0x0A, count - start).map { base.distance(to: UnsafeRawPointer($0)) } ?? count
                defer { start = end + 1 }
                let line = base + start
                let length = end - start
                // Request blobs repeat the whole conversation, tool calls included. They are most of the file; skip them unread.
                if memmem(line, min(length, 60), requestBlob, requestBlob.count) != nil { continue }
                let relevant = memmem(line, length, toolName, toolName.count) != nil
                    || memmem(line, length, linkPart, linkPart.count) != nil
                    || pending.keys.contains { id in id.utf8.withContiguousStorageIfAvailable { memmem(line, length, $0.baseAddress, $0.count) != nil } ?? false }
                guard relevant,
                      let record = try? JSONSerialization.jsonObject(with: Data(bytes: line, count: length)) as? [String: Any],
                      let blocks = (record["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
                for block in blocks {
                    switch block["type"] as? String {
                    case "tool_use":
                        guard block["name"] as? String == "Artifact", let id = block["id"] as? String,
                              let input = block["input"] as? [String: Any] else { continue }
                        pending[id] = Call(input: input, at: date(record["timestamp"]))
                    case "tool_result":
                        guard let id = block["tool_use_id"] as? String, let call = pending.removeValue(forKey: id),
                              block["is_error"] as? Bool != true else { continue }
                        if let event = event(for: call, result: text(of: block["content"]), sessionId: sessionId) { events.append(event) }
                    default:
                        continue
                    }
                }
            }
        }
        return events
    }

    private static func event(for call: Call, result: String, sessionId: String) -> ArtifactEvent? {
        let input = call.input
        let action = input["action"] as? String
        let shown: Bool
        var filePath: String?
        switch action {
        case nil, "publish":
            guard let path = input["file_path"] as? String, input["asset"] as? Bool != true else { return nil }
            shown = true
            filePath = path
        case "open":
            shown = true
        case "read":
            shown = false
        default:
            return nil
        }
        guard let url = firstLink(in: input["url"] as? String ?? "") ?? firstLink(in: result) else { return nil }
        let isPublish = filePath != nil
        return ArtifactEvent(url: url, sessionId: sessionId, shown: shown,
                             title: isPublish ? nonEmpty(input["title"]) : nil,
                             description: isPublish ? nonEmpty(input["description"]) : nil,
                             filePath: filePath, at: call.at)
    }

    static func firstLink(in text: String) -> URL? {
        guard let match = link.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return URL(string: String(text[range]))
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// A tool result is either a string or a list of blocks that carry text.
    private static func text(of content: Any?) -> String {
        if let text = content as? String { return text }
        let blocks = content as? [[String: Any]] ?? []
        return blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
    }

    private static func date(_ value: Any?) -> Date {
        guard let text = value as? String else { return Date(timeIntervalSince1970: 0) }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: 0)
    }
}
