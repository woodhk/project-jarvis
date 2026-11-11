import Foundation

/// Picks only apps and websites named outright. Used until the full picker is wired in, and as a safe stand-in.
public struct NameOnlyPicker: Picking {
    public init() {}

    public func pick(transcript: String, cards: CardSnapshot, context: PickContext) async -> Outcome {
        NameMatcher(apps: cards.apps, sites: cards.sites).match(transcript).map(Outcome.open) ?? .nothing
    }
}
