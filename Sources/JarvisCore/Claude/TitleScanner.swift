import Foundation

/// Finds a session's title in its history file. The file can be tens of megabytes, so only the few short lines
/// that can be title records are parsed.
public enum TitleScanner {
    private static let needle = Array("-title\"".utf8)
    private static let longestTitleLine = 400

    /// The title from the last `ai-title` or `custom-title` record, or nil.
    public static func lastTitle(in historyFile: URL) -> String? {
        guard let data = try? Data(contentsOf: historyFile, options: .mappedIfSafe), !data.isEmpty else { return nil }
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> String? in
            guard let base = bytes.baseAddress else { return nil }
            let count = bytes.count
            var last: String?
            var offset = 0
            while offset < count,
                  let hit = memmem(base + offset, count - offset, needle, needle.count) {
                let position = base.distance(to: UnsafeRawPointer(hit))
                var start = position
                while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
                let end = memchr(base + position, 0x0A, count - position).map { base.distance(to: UnsafeRawPointer($0)) } ?? count
                if end - start < longestTitleLine,
                   let found = title(inLine: Data(bytes: base + start, count: end - start)) {
                    last = found
                }
                offset = end + 1          // a long line may mention a title many times; skip the whole line
            }
            return last
        }
    }

    private static func title(inLine line: Data) -> String? {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        let value: Any?
        switch record["type"] as? String {
        case "ai-title": value = record["aiTitle"]
        case "custom-title": value = record["customTitle"]
        default: value = nil
        }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
