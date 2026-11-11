import Foundation

/// A short memory between requests. "No, the artifact in Chrome", said just after a request that went wrong, only
/// makes sense together with that request. So does "open the artifact" after a request that opened nothing.
public enum FollowUp {
    /// How long the request before stays in mind.
    public static let window: TimeInterval = 30
    private static let corrections: [[String]] = [["no"], ["know"], ["nope"], ["not"], ["i", "meant"], ["i", "said"], ["sorry"], ["actually"]]

    /// The earlier request and the new words as one text, when the new words continue or correct the earlier request.
    /// Nil when the new words stand alone.
    public static func joined(new: String, earlier: String?, secondsSince: TimeInterval, earlierOpened: Bool) -> String? {
        guard let earlier, !earlier.isEmpty, secondsSince <= window else { return nil }
        let words = Normalizer.words(new)
        if words == ["back"] || words == ["go", "back"] || Picker.choiceIndex(words) != nil || Picker.asksForList(words)
            || Picker.appVerb(words) != nil || Picker.saysYes(words) || Picker.saysNo(words) { return nil }
        let corrects = corrections.contains { words.starts(with: $0) }
        let saysNothingItself = FallbackMatcher.contentWords(new).isEmpty
        guard corrects || (!earlierOpened && saysNothingItself) else { return nil }
        return String((earlier + ". " + new).suffix(400))
    }
}
