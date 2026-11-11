import Foundation

/// Websites that are known without being typed into the settings file. Each has a host of its own, because Chrome
/// finds an open tab by its host. Names are matched without case or spaces, so "Git Hub" needs no entry of its own.
public enum KnownSites {
    public static let all: [SiteCard] = [
        ("YouTube", [], "https://www.youtube.com/"),
        ("Instagram", [], "https://www.instagram.com/"),
        ("Gmail", ["Google Mail"], "https://mail.google.com/"),
        ("Google", [], "https://www.google.com/"),
        ("Google Calendar", [], "https://calendar.google.com/"),
        ("Google Drive", [], "https://drive.google.com/"),
        ("Google Docs", [], "https://docs.google.com/"),
        ("Google Meet", [], "https://meet.google.com/"),
        ("Gemini", [], "https://gemini.google.com/app"),
        ("GitHub", [], "https://github.com/"),
        ("LinkedIn", [], "https://www.linkedin.com/"),
        ("X", ["Twitter"], "https://x.com/"),
        ("Facebook", [], "https://www.facebook.com/"),
        ("WhatsApp", [], "https://web.whatsapp.com/"),
        ("Reddit", [], "https://www.reddit.com/"),
        ("Netflix", [], "https://www.netflix.com/"),
        ("TikTok", [], "https://www.tiktok.com/"),
        ("Pinterest", [], "https://www.pinterest.com/"),
        ("Twitch", [], "https://www.twitch.tv/"),
        ("Wikipedia", [], "https://www.wikipedia.org/"),
        ("ChatGPT", [], "https://chatgpt.com/"),
        ("Claude", [], "https://claude.ai/"),
        ("Notion", [], "https://www.notion.so/"),
        ("Figma", [], "https://www.figma.com/"),
        ("Canva", [], "https://www.canva.com/"),
        ("Spotify", [], "https://open.spotify.com/"),
        ("Discord", [], "https://discord.com/app"),
        ("Slack", [], "https://app.slack.com/"),
        ("Dropbox", [], "https://www.dropbox.com/"),
        ("iCloud", [], "https://www.icloud.com/"),
        ("Stripe", [], "https://dashboard.stripe.com/"),
        ("Vercel", [], "https://vercel.com/"),
        ("Supabase", [], "https://supabase.com/dashboard"),
    ].map { SiteCard(name: $0.0, aliases: $0.1, url: URL(string: $0.2)!, builtIn: true) }

    /// The user's own websites, unchanged and first, then the built-in ones. A built-in site gives way to anything
    /// that already has its name: a website of the user's, or an installed app ("open Spotify" means the app when
    /// there is one). A second name that is already in use is dropped from the built-in site only.
    /// `folders` are the built-in folders (`KnownFolders`); they follow the same rules.
    public static func merged(user: [SiteCard], apps: [AppCard], folders: [SiteCard] = []) -> [SiteCard] {
        var taken = Set<String>()
        for site in user { for name in [site.name] + site.aliases { taken.insert(Normalizer.compact(name)) } }
        for app in apps { for name in [app.name] + app.aliases { taken.insert(Normalizer.compact(name)) } }
        var result = user
        for var site in all + folders where !taken.contains(Normalizer.compact(site.name)) {
            site.aliases = site.aliases.filter { !taken.contains(Normalizer.compact($0)) }
            result.append(site)
        }
        return result
    }
}
