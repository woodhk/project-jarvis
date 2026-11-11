import Foundation

/// Finds an app or website that the speaker named outright. No network, no guessing.
public struct NameMatcher: Sendable {
    private let apps: [AppCard]
    private let sites: [SiteCard]

    public init(apps: [AppCard], sites: [SiteCard]) {
        self.apps = apps
        self.sites = sites
    }

    /// A target when the phrase, without its lead-in, equals a name or alias once case and spaces are ignored.
    /// Websites are checked before apps.
    public func match(_ transcript: String) -> Target? {
        let spoken = Normalizer.compact(Normalizer.stripLead(transcript))
        guard !spoken.isEmpty else { return nil }
        let cards = CardSnapshot()
        if let site = sites.first(where: { ([$0.name] + $0.aliases).contains { Normalizer.compact($0) == spoken } }) {
            return cards.target(for: site)
        }
        if let app = apps.first(where: { ([$0.name] + $0.aliases).contains { Normalizer.compact($0) == spoken } }) {
            return cards.target(for: app)
        }
        return nil
    }
}
