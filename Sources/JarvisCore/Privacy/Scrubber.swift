import Foundation

/// Removes what must never leave this Mac from a piece of text: links, email addresses, file paths,
/// long tokens (keys, identifiers) and the user's own name.
public struct Scrubber: Sendable {
    private static let link = try! NSRegularExpression(pattern: #"https?://\S+"#, options: [.caseInsensitive])
    private static let email = try! NSRegularExpression(pattern: #"\S+@\S+"#)
    private static let path = try! NSRegularExpression(pattern: #"[/~][\w./-]+"#)
    private static let token = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_-])(?=[A-Za-z0-9_-]*[A-Za-z])(?=[A-Za-z0-9_-]*[0-9])[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_-])"#)

    private let names: NSRegularExpression?

    public init(userNames: [String]) {
        let words = userNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .map(NSRegularExpression.escapedPattern(for:))
        // A name counts when no letter comes before it and no small letter comes after it: "Sam", "sam_videos",
        // "SamNotes" and "sam's" all lose the name, while "samples" is left alone.
        names = words.isEmpty ? nil : try? NSRegularExpression(pattern: "(?<![A-Za-z])(?i:" + words.joined(separator: "|") + ")(?![a-z])")
    }

    public func scrub(_ text: String) -> String {
        scrub(text, removingNames: true)
    }

    /// `removingNames: false` is for callers that drop names themselves, word by word.
    /// Each rule runs only when the text holds a character that rule needs, which keeps long histories quick to scan.
    func scrub(_ text: String, removingNames: Bool) -> String {
        var result = text
        var hasSlash = false, hasAt = false, hasDigit = false, hasColonSlash = false
        var previous: UInt8 = 0
        for byte in text.utf8 {
            if byte == 0x2F { hasSlash = true; if previous == 0x3A { hasColonSlash = true } }
            else if byte == 0x7E { hasSlash = true }
            else if byte == 0x40 { hasAt = true }
            else if byte >= 0x30 && byte <= 0x39 { hasDigit = true }
            previous = byte
        }
        var rules: [NSRegularExpression] = []
        if hasColonSlash { rules.append(Self.link) }
        if hasAt { rules.append(Self.email) }
        if hasSlash { rules.append(Self.path) }
        if hasDigit { rules.append(Self.token) }
        if removingNames, let names { rules.append(names) }
        for rule in rules {
            result = rule.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The words of the account's full name and short name, lowercased, three letters or more.
    public static func systemUserNames() -> [String] {
        let raw = NSFullUserName() + " " + NSUserName()
        let words = raw.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 }
        return Array(Set(words)).sorted()
    }
}
