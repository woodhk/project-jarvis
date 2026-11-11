import Foundation
import Testing
@testable import JarvisCore

/// From the fifth hand test: "open Instagram on Google Chrome" opened Chrome and no Instagram, and "open Instagram"
/// opened nothing. Well-known websites are now known without being typed into the settings file, and "on Google
/// Chrome" at the end of a request says where to open, not what.
@Suite struct KnownSitesTests {
    var b: PickerBench
    var cards: CardSnapshot
    let chrome = AppCard(name: "Google Chrome", aliases: ["Chrome"], path: "/Applications/Google Chrome.app")

    init() throws {
        b = try PickerBench()
        cards = b.cards
        cards.apps.append(chrome)
        cards.sites = KnownSites.merged(user: cards.sites, apps: cards.apps)
    }

    func site(_ name: String) -> Target { cards.target(for: cards.sites.first { $0.name == name }!) }

    @Test func whereToOpenItIsNotPartOfTheName() {
        #expect(Normalizer.stripLead("open Instagram on Google Chrome") == "instagram")
        #expect(Normalizer.stripLead("Open Instagram in Chrome.") == "instagram")
        #expect(Normalizer.stripLead("can you open Instagram on Chrome please") == "instagram")
        #expect(Normalizer.stripLead("open YouTube in the browser") == "youtube")
        #expect(Normalizer.stripLead("open the GitHub website in a new tab") == "github")
        #expect(Normalizer.stripLead("open Google Chrome") == "google chrome")           // the app itself
        #expect(Normalizer.stripLead("open the artifact in Chrome") == "artifact")
        #expect(Normalizer.stripLead("open in Chrome") == "in chrome")                   // nothing would be left: untouched
    }

    @Test func theBuiltInListIsSound() throws {
        let all = KnownSites.all
        #expect(all.count >= 15)
        #expect(all.filter { !$0.builtIn }.isEmpty)
        #expect(all.first { $0.name == "Instagram" }?.url == URL(string: "https://www.instagram.com/"))
        var names = Set<String>(), hosts = Set<String>()
        for site in all {
            #expect(site.url.scheme == "https", "\(site.name)")
            var host = try #require(site.url.host, "\(site.name)")
            if host.hasPrefix("www.") { host.removeFirst(4) }
            // Chrome finds an open tab by its host, so two sites on one host could not be told apart.
            #expect(hosts.insert(host).inserted, "two sites share \(host)")
            for name in [site.name] + site.aliases {
                #expect(names.insert(Normalizer.compact(name)).inserted, "the name \(name) is used twice")
            }
        }
    }

    @Test func yourOwnListAndInstalledAppsComeFirst() {
        let mine = [SiteCard(name: "instagram", aliases: [], url: URL(string: "https://www.instagram.com/direct/inbox/")!),
                    SiteCard(name: "Shop admin", aliases: ["twitter"], url: URL(string: "https://example.com/admin")!)]
        let apps = [AppCard(name: "Spotify", aliases: [], path: "/Applications/Spotify.app"),
                    AppCard(name: "Mail", aliases: ["Google Mail"], path: "/System/Applications/Mail.app")]
        let merged = KnownSites.merged(user: mine, apps: apps)
        #expect(Array(merged.prefix(2)) == mine)                                               // unchanged and first
        #expect(merged.filter { Normalizer.compact($0.name) == "instagram" }.count == 1)       // yours replaces the built-in one
        #expect(!merged.contains { $0.name == "Spotify" })                                     // the installed app is what "open Spotify" means
        #expect(merged.first { $0.name == "X" }?.aliases == [])                                // a name you use elsewhere stays yours
        #expect(merged.first { $0.name == "Gmail" }?.aliases == [])
        #expect(KnownSites.all.first { $0.name == "X" }?.aliases == ["Twitter"])
        #expect(merged.contains { $0.name == "Reddit" && $0.builtIn })
        #expect(KnownSites.merged(user: [], apps: []).count == KnownSites.all.count)
    }

    @Test(arguments: ["open Instagram on Google Chrome", "open Instagram", "Open Instagram in Chrome.", "can you open the Instagram website",
                      "take me to Instagram please"])
    func instagramOpensHoweverItIsAskedFor(_ phrase: String) async {
        let (p, jev, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: phrase, cards: cards, context: b.idle) == .open(site("Instagram")))
        #expect(jev.calls == 0)
        #expect(site("Instagram").destination == .site(url: URL(string: "https://www.instagram.com/")!))
    }

    @Test func chromeItselfStillOpens() async {
        let (p, _, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "open Google Chrome", cards: cards, context: b.idle) == .open(cards.target(for: chrome)))
        #expect(await p.pick(transcript: "open Chrome", cards: cards, context: b.idle) == .open(cards.target(for: chrome)))
    }

    // Before, "open <unknown> on Google Chrome" found "Google Chrome" inside the sentence and opened that.
    @Test func aWebsiteThatIsNotKnownOpensNothingAndSaysSo() async {
        let (p, _, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "open Flibbertigibbet on Google Chrome", cards: cards, context: b.idle) == .unknownName)
        #expect(await p.pick(transcript: "open Flibbertigibbet", cards: cards, context: b.idle) == .unknownName)
    }

    // A built-in website must be heard exactly: "motion" is a word about work, not a misheard "Notion".
    @Test func aBuiltInNameIsNeverGuessedFromANearMiss() async {
        let (p, jev, _) = b.make(kind: "session", session: ["s-gif": 0.9])
        #expect(await p.pick(transcript: "open motion", cards: cards, context: b.idle) == .open(b.target("s-gif")))
        #expect(await p.pick(transcript: "open edit", cards: cards, context: b.idle) == .open(b.target("s-gif")))
        #expect(jev.calls == 2)
        // A website of your own, like an app, may still be a little misheard.
        let (q, _, _) = b.make(kind: "app_or_website")
        #expect(await q.pick(transcript: "open you tub", cards: cards, context: b.idle) == .open(site("YouTube")))
        // And a built-in name said exactly inside a longer sentence is found.
        #expect(await q.pick(transcript: "can you bring up the Reddit thing for me", cards: cards, context: b.idle) == .open(site("Reddit")))
    }

    @Test func builtInNamesDoNotCrowdTheSpeechHints() {
        var own = cards
        own.sites = KnownSites.merged(user: [SiteCard(name: "Shop admin", aliases: [], url: URL(string: "https://example.com/admin")!)], apps: [])
        let hint = own.vocabularyHint()
        #expect(hint.contains("Shop admin"))
        #expect(!hint.contains("Reddit"))
        #expect(!hint.contains("Instagram,"))
    }

    @Test func theSettingsFileDoesNotGainAField() throws {
        let data = try JSONEncoder().encode(KnownSites.all[0])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["name", "aliases", "url"])
        let decoded = try JSONDecoder().decode(SiteCard.self, from: data)
        #expect(decoded.builtIn == false)
        #expect(decoded.name == KnownSites.all[0].name)
    }
}
