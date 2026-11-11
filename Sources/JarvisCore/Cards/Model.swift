import Foundation

// Every possible destination is a card. This file holds the cards and the few types that travel with them.

public enum HostApp: String, Codable, Sendable {
    case terminal, vscode
}

/// One open Claude Code session.
public struct SessionCard: Equatable, Sendable, Codable {
    public var id: String
    public var pid: Int32
    public var shellPid: Int32
    public var tty: String
    public var host: HostApp
    public var folderPath: String
    public var folderLabel: String
    public var label: String
    /// Distinctive words the user typed in the session.
    public var gist: [String]
    /// Distinctive words from Claude's replies in the session: what it is about, even when the user never typed it.
    public var replyGist: [String]
    /// When something was last written in the session (its history file changed), if known.
    public var lastActive: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        pid = try c.decode(Int32.self, forKey: .pid)
        shellPid = try c.decode(Int32.self, forKey: .shellPid)
        tty = try c.decode(String.self, forKey: .tty)
        host = try c.decode(HostApp.self, forKey: .host)
        folderPath = try c.decode(String.self, forKey: .folderPath)
        folderLabel = try c.decode(String.self, forKey: .folderLabel)
        label = try c.decode(String.self, forKey: .label)
        gist = try c.decode([String].self, forKey: .gist)
        replyGist = try c.decodeIfPresent([String].self, forKey: .replyGist) ?? []
        lastActive = try c.decodeIfPresent(Date.self, forKey: .lastActive)
    }

    public init(id: String, pid: Int32, shellPid: Int32, tty: String, host: HostApp, folderPath: String,
                folderLabel: String, label: String, gist: [String], replyGist: [String] = [], lastActive: Date? = nil) {
        self.replyGist = replyGist
        self.lastActive = lastActive
        self.id = id
        self.pid = pid
        self.shellPid = shellPid
        self.tty = tty
        self.host = host
        self.folderPath = folderPath
        self.folderLabel = folderLabel
        self.label = label
        self.gist = gist
    }
}

/// How a session is connected to an artifact. `shown` means it published or opened the page; false means it only read it.
public struct ArtifactLink: Equatable, Sendable, Codable {
    public var sessionId: String
    public var shown: Bool
    public var at: Date

    public init(sessionId: String, shown: Bool, at: Date) {
        self.sessionId = sessionId
        self.shown = shown
        self.at = at
    }
}

public struct ArtifactCard: Equatable, Sendable, Codable {
    public var url: URL
    public var title: String?
    public var description: String?
    public var links: [ArtifactLink]

    public init(url: URL, title: String?, description: String?, links: [ArtifactLink]) {
        self.url = url
        self.title = title
        self.description = description
        self.links = links
    }
}

public struct AppCard: Equatable, Sendable, Codable {
    public var name: String
    public var aliases: [String]
    public var path: String

    public init(name: String, aliases: [String], path: String) {
        self.name = name
        self.aliases = aliases
        self.path = path
    }
}

public struct SiteCard: Equatable, Sendable, Codable {
    public var name: String
    public var aliases: [String]
    public var url: URL
    /// True for a website from the built-in list (`KnownSites`), false for one from the user's settings file.
    /// Not stored: the settings file holds only the user's own.
    public var builtIn = false

    private enum CodingKeys: String, CodingKey {
        case name, aliases, url
    }

    public init(name: String, aliases: [String], url: URL, builtIn: Bool = false) {
        self.name = name
        self.aliases = aliases
        self.url = url
        self.builtIn = builtIn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        url = try c.decode(URL.self, forKey: .url)
    }
}

/// Where a card lives, in the terms an opener needs.
public enum Destination: Equatable, Sendable, Codable {
    case terminalTab(tty: String)
    case vscodeTerminal(shellPid: Int32, folderPath: String)
    /// Chrome: a tab on the same host, otherwise a new tab.
    case site(url: URL)
    /// Chrome: a tab whose URL starts with this, otherwise a new tab.
    case artifact(url: URL)
    case app(path: String)
    /// Finder: a window on this folder.
    case folder(path: String)
}

/// A destination together with the words the pill shows for it.
public struct Target: Equatable, Sendable {
    public var destination: Destination
    public var title: String
    public var subtitle: String
    public var cardKey: String

    public init(destination: Destination, title: String, subtitle: String, cardKey: String) {
        self.destination = destination
        self.title = title
        self.subtitle = subtitle
        self.cardKey = cardKey
    }
}

/// The card in front when the key went down, if any.
public enum FrontCard: Equatable, Sendable {
    case session(id: String)
    case artifact(url: URL)
    case none
}

public struct PickContext: Equatable, Sendable {
    public var front: FrontCard
    /// True while two choices are showing.
    public var choosing: Bool

    public init(front: FrontCard, choosing: Bool) {
        self.front = front
        self.choosing = choosing
    }
}

/// What can be done to a running app besides bringing it forward.
public enum AppAction: String, Equatable, Sendable {
    /// "Close": the app's windows go away and the app keeps running. Nothing is closed for good, so nothing is lost.
    case hide
    /// "Quit": the app is asked to quit in the normal way, so it can still ask about unsaved work.
    case quit
}

/// A request to close or quit one app.
public struct AppRequest: Equatable, Sendable {
    public enum Ask: Equatable, Sendable {
        /// The name was not heard exactly.
        case unsureOfName
        /// Quitting would end this many Claude Code sessions that run inside the app.
        case endsSessions(Int)
        /// "Quit it": the app was not named, it is the one in front.
        case inFront
    }

    /// How many open Claude Code sessions run inside the app with this name.
    public static func sessionsInside(appNamed name: String, cards: CardSnapshot) -> Int {
        switch Normalizer.compact(name) {
        case "terminal": return cards.sessions.filter { $0.host == .terminal }.count
        case "visualstudiocode", "code": return cards.sessions.filter { $0.host == .vscode }.count
        default: return 0
        }
    }

    public var action: AppAction
    public var target: Target
    /// Why Jarvis asks before it acts, or nil when it acts at once.
    public var ask: Ask?

    public init(action: AppAction, target: Target, ask: Ask?) {
        self.action = action
        self.target = target
        self.ask = ask
    }
}

public enum Outcome: Equatable, Sendable {
    case open(Target)
    /// One or two targets to offer. `rememberable` is false when they came from the fallback or from what was in front.
    case choices([Target], rememberable: Bool)
    /// Every open session, for the user to pick from by number: the answer to "show all sessions". May be empty.
    case list([Target])
    /// Close or quit an app.
    case app(AppRequest)
    /// "Close it", "quit this": the app in front, whichever that is.
    case appInFront(AppAction)
    /// "Close" or "quit" was said, but no app was named. Nothing else is ever closed.
    case appUnknown(AppAction)
    case nothing
    /// An app or a website was asked for by a name that is not known.
    case unknownName
    case back
    case pickChoice(Int)
    /// "No" or "cancel", said while choices or a question are on show: they go away and nothing happens.
    case cancel
}

public protocol Picking: Sendable {
    func pick(transcript: String, cards: CardSnapshot, context: PickContext) async -> Outcome
    /// Called when fn goes down, so slow set-up can start before the request.
    func prepare()
}

extension Picking {
    public func prepare() {}
}

/// All cards at one moment.
public struct CardSnapshot: Equatable, Sendable, Codable {
    public var sessions: [SessionCard] = []
    public var artifacts: [ArtifactCard] = []
    public var apps: [AppCard] = []
    public var sites: [SiteCard] = []
    /// Folders below the roots named in the settings file (an external drive, say).
    public var folders: [FolderCard] = []

    public init(sessions: [SessionCard] = [], artifacts: [ArtifactCard] = [], apps: [AppCard] = [], sites: [SiteCard] = [],
                folders: [FolderCard] = []) {
        self.sessions = sessions
        self.artifacts = artifacts
        self.apps = apps
        self.sites = sites
        self.folders = folders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try c.decode([SessionCard].self, forKey: .sessions)
        artifacts = try c.decode([ArtifactCard].self, forKey: .artifacts)
        apps = try c.decode([AppCard].self, forKey: .apps)
        sites = try c.decode([SiteCard].self, forKey: .sites)
        folders = try c.decodeIfPresent([FolderCard].self, forKey: .folders) ?? []
    }

    /// A folder is shown with where it is: "Finder · vault › Brand › Videos".
    public func target(for folder: FolderCard) -> Target {
        Target(destination: .folder(path: folder.path), title: folder.name,
               subtitle: folder.trail.isEmpty ? "Finder" : "Finder · " + folder.trail.joined(separator: " › "), cardKey: "folder:\(folder.path)")
    }

    public func target(for session: SessionCard) -> Target {
        switch session.host {
        case .terminal:
            return Target(destination: .terminalTab(tty: session.tty), title: session.label,
                          subtitle: "Terminal · \(session.folderLabel)", cardKey: "session:\(session.id)")
        case .vscode:
            return Target(destination: .vscodeTerminal(shellPid: session.shellPid, folderPath: session.folderPath), title: session.label,
                          subtitle: "VS Code · \(session.folderLabel)", cardKey: "session:\(session.id)")
        }
    }

    /// A website opens in Chrome. A card with a file address is a folder and opens in Finder.
    public func target(for site: SiteCard) -> Target {
        if site.url.isFileURL {
            return Target(destination: .folder(path: site.url.path), title: site.name, subtitle: "Finder", cardKey: "site:\(site.name)")
        }
        return Target(destination: .site(url: site.url), title: site.name, subtitle: "Chrome", cardKey: "site:\(site.name)")
    }

    public func target(for app: AppCard) -> Target {
        Target(destination: .app(path: app.path), title: app.name, subtitle: "app", cardKey: "app:\(app.path)")
    }
}

extension CardSnapshot {
    /// Words the speaker is likely to say, for the speech recogniser: session names, folders, the first gist terms,
    /// artifact titles and website names, then `extraWords`. Hyphens and underscores become spaces, repeats are
    /// dropped, and the list stops before it would pass `maxChars`.
    public func vocabularyHint(extraWords: [String] = [], maxChars: Int = 600) -> String {
        var items: [String] = ["Claude Code session", "artifact", "terminal"]
        items += sessions.map(\.label)
        items += sessions.map(\.folderLabel)
        for session in sessions { items += session.gist.prefix(3) }
        for session in sessions { items += session.replyGist.prefix(3) }
        items += artifacts.compactMap(\.title)
        // Built-in websites are household names the recogniser spells without help; they would only crowd out the rest.
        items += sites.filter { !$0.builtIn }.map(\.name)
        items += extraWords
        var seen = Set<String>()
        var hint = ""
        for item in items {
            let spoken = item.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
                .split(separator: " ").joined(separator: " ")
            guard !spoken.isEmpty, seen.insert(spoken.lowercased()).inserted else { continue }
            let next = hint.isEmpty ? spoken : hint + ", " + spoken
            if next.count > maxChars { break }
            hint = next
        }
        return hint
    }
}

extension CardSnapshot {
    /// The artifacts of one session: those it published or opened, newest first, then those it only read, newest first.
    public func artifacts(of sessionId: String) -> [ArtifactCard] {
        func linked(shown: Bool) -> [ArtifactCard] {
            artifacts.compactMap { card -> (card: ArtifactCard, at: Date)? in
                guard let link = card.links.first(where: { $0.sessionId == sessionId && $0.shown == shown }) else { return nil }
                return (card, link.at)
            }.sorted { $0.at > $1.at }.map(\.card)
        }
        return linked(shown: true) + linked(shown: false)
    }

    /// The open sessions that published or opened the artifact, the most recent first.
    public func openSessions(linkedTo url: URL) -> [(session: SessionCard, at: Date)] {
        guard let card = artifacts.first(where: { $0.url == url }) else { return [] }
        return card.links.filter(\.shown).compactMap { link -> (session: SessionCard, at: Date)? in
            sessions.first { $0.id == link.sessionId }.map { ($0, link.at) }
        }.sorted { $0.at > $1.at }
    }

    public func target(for artifact: ArtifactCard) -> Target {
        let firstWords = artifact.description.map { $0.split(separator: " ").prefix(6).joined(separator: " ") }
        let title = [artifact.title, firstWords].compactMap { $0 }.first { !$0.isEmpty } ?? "Artifact"
        return Target(destination: .artifact(url: artifact.url), title: title, subtitle: "Chrome · artifact",
                      cardKey: "artifact:\(artifact.url.absoluteString)")
    }
}

extension CardSnapshot {
    /// Gives each artifact that has no title the title of the Chrome tab that shows it. A session that only opened
    /// a page never recorded its title, but the tab has it.
    public func takingTitles(fromTabs tabs: [(url: String, title: String)]) -> CardSnapshot {
        var copy = self
        for index in copy.artifacts.indices where copy.artifacts[index].title == nil {
            let link = copy.artifacts[index].url.absoluteString
            let tab = tabs.first { tab in
                tab.url == link || tab.url.hasPrefix(link + "/") || tab.url.hasPrefix(link + "?") || tab.url.hasPrefix(link + "#")
            }
            guard var title = tab?.title.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            for ending in [" | Claude", " - Claude", " – Claude", " — Claude"] where title.hasSuffix(ending) {
                title = String(title.dropLast(ending.count)).trimmingCharacters(in: .whitespaces)
            }
            if !title.isEmpty, title != "Claude" { copy.artifacts[index].title = title }
        }
        return copy
    }
}
