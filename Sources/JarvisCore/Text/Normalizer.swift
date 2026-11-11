import Foundation

/// Brings spoken text and card names to one comparable form.
public enum Normalizer {
    private static let leads: [[String]] = [
        ["take", "me", "back", "to"], ["take", "me", "to"], ["go", "back", "to"], ["switch", "back", "to"], ["open", "up"], ["go", "to"],
        ["show", "me"], ["switch", "to"], ["bring", "up"], ["back", "to"], ["return", "to"], ["open"], ["show"], ["launch"],
    ]
    /// Words that may come before the request itself: "wait, open Google Chrome", "okay so can you open…".
    private static let smallTalk: Set<String> = ["wait", "okay", "ok", "oh", "so", "now", "and", "then", "hey", "jarvis", "um", "uh", "well",
                                                 "right", "alright", "actually", "yeah", "yes", "no", "sorry", "also", "just"]
    private static let openings: [[String]] = [["can", "you"], ["could", "you"], ["would", "you"], ["will", "you"], ["can", "we"], ["please"]]
    private static let fillers: Set<String> = ["the", "my"]
    private static let endings: Set<String> = ["app", "website", "please"]
    /// Where to open it, said after what to open: "open Instagram on Google Chrome". Chrome is the only browser used.
    private static let places: [[String]] = [
        ["on", "google", "chrome"], ["in", "google", "chrome"], ["on", "chrome"], ["in", "chrome"], ["in", "the", "browser"],
        ["in", "my", "browser"], ["in", "a", "browser"], ["on", "the", "web"], ["in", "a", "new", "tab"], ["in", "a", "tab"],
        ["in", "the", "finder"], ["in", "finder"], ["on", "finder"], ["with", "finder"],
    ]

    /// Lowercased words with punctuation removed. A hyphen or underscore separates words; an apostrophe does not.
    public static func words(_ s: String) -> [String] {
        let cleaned = s.lowercased().unicodeScalars.map { scalar -> Character in
            if scalar == "'" || scalar == "’" { return "\u{0}" }
            return CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(cleaned.filter { $0 != "\u{0}" }).split(separator: " ").map(String.init)
    }

    /// The words joined with no spaces, so "Chat GPT" equals "ChatGPT".
    public static func compact(_ s: String) -> String {
        words(s).joined()
    }

    /// The words left after removing a lead-in such as "open" or "take me to", a following "the" or "my",
    /// and a closing "app", "website" or "please". Joined with single spaces.
    public static func stripLead(_ s: String) -> String {
        var w = words(s)
        // Small talk is dropped only when a request follows it: "now playing" is left as it is.
        let talk = w.prefix(while: smallTalk.contains).count
        if talk > 0, talk < w.count {
            let rest = Array(w.dropFirst(talk))
            if openings.contains(where: { rest.starts(with: $0) }) || leads.contains(where: { rest.starts(with: $0) }) { w = rest }
        }
        if let opening = openings.first(where: { w.starts(with: $0) }) { w.removeFirst(opening.count) }
        // Speech recognition sometimes writes "OpenChat GPT": the lead-in glued to the next word.
        if let first = w.first, first.hasPrefix("open"), first.count > 4, !leads.contains(where: { w.starts(with: $0) }) {
            w[0] = String(first.dropFirst(4))
            w.insert("open", at: 0)
        }
        if let lead = leads.first(where: { w.starts(with: $0) }) {
            w.removeFirst(lead.count)
            if let first = w.first, fillers.contains(first) { w.removeFirst() }
        }
        var changed = true
        while changed {
            changed = false
            while let last = w.last, endings.contains(last), w.count > 1 {
                w.removeLast()
                changed = true
            }
            if let place = places.first(where: { w.count > $0.count && Array(w.suffix($0.count)) == $0 }) {
                w.removeLast(place.count)
                changed = true
            }
        }
        return w.joined(separator: " ")
    }
}
