import Foundation
import JarvisCore

/// Keeps the cards fresh: open sessions with their gists, websites from the settings file, and installed apps.
/// `refresh()` rebuilds in the background; `snapshot` is always the last finished build.
public final class CardStore: CardProviding, @unchecked Sendable {
    private let configFile: URL
    private let homeDir: URL
    private let claudeDir: URL
    private let reader: SessionReader
    private let gistBuilder: GistBuilder
    private let replyGists: ReplyGistBuilder
    private let catalog: AppCatalog
    private let artifactIndex: ArtifactIndex?
    /// The claude.ai tabs open in Chrome (address and title), for pages whose title no session recorded.
    private let chromeTabs: (@Sendable () -> [(url: String, title: String)])?
    /// Where the cards are written for diagnosis (this Mac only), or nil.
    private let debugFile: URL?
    /// Where the list of folders is kept between runs, so a drive that is unplugged is still known by name. Nil: no folders.
    private let folderCache: URL?
    /// How often the folders are listed again.
    static let folderInterval: TimeInterval = 300
    private let artifactQueue = DispatchQueue(label: "local.jarvis.switcher.artifacts", qos: .utility)
    private let queue = DispatchQueue(label: "local.jarvis.switcher.cards", qos: .userInitiated)

    private let lock = NSLock()
    private var current = CardSnapshot()
    private var running = false
    private var again = false
    private var allArtifacts: [ArtifactCard] = []
    private var tabs: [(url: String, title: String)] = []
    private var scanningArtifacts = false
    private var folderCards: [FolderCard] = []
    private var scanningFolders = false
    private var foldersListedAt = Date.distantPast

    // Only touched while a rebuild runs (one at a time).
    private var config = Config.default
    private var gistCache: (stamp: String, gists: [String: [String]])?
    private var historyFiles: [String: URL] = [:]

    public init(configFile: URL, claudeDir: URL, homeDir: URL, inspector: ProcessInspecting, catalog: AppCatalog, userNames: [String],
                artifactIndex: ArtifactIndex? = nil, chromeTabs: (@Sendable () -> [(url: String, title: String)])? = nil,
                debugFile: URL? = nil, folderCache: URL? = nil) {
        self.debugFile = debugFile
        self.folderCache = folderCache
        self.artifactIndex = artifactIndex
        self.chromeTabs = chromeTabs
        self.configFile = configFile
        self.homeDir = homeDir
        self.claudeDir = claudeDir
        self.reader = SessionReader(claudeDir: claudeDir, homeDir: homeDir, inspector: inspector)
        self.gistBuilder = GistBuilder(userNames: userNames)
        self.replyGists = ReplyGistBuilder(userNames: userNames)
        self.catalog = catalog
    }

    public var snapshot: CardSnapshot {
        lock.withLock { current }
    }

    /// Starts a rebuild in the background. A call made while one is running is merged into one more run after it.
    public func refresh() {
        let start = lock.withLock { () -> Bool in
            if running {
                again = true
                return false
            }
            running = true
            return true
        }
        refreshArtifacts()
        refreshFolders()
        guard start else { return }
        queue.async { [self] in
            var more = true
            while more {
                rebuild()
                more = lock.withLock {
                    if again {
                        again = false
                        return true
                    }
                    running = false
                    return false
                }
            }
        }
    }

    /// Builds everything now, on the calling thread: for the command-line checks, which have no time to wait.
    public func loadNow() {
        rebuildArtifacts()
        rebuildFolders()
        rebuild()
    }

    /// Lists the folders again in the background: every few minutes, or now when `force` is set (a drive was
    /// plugged in or taken out).
    public func refreshFolders(force: Bool = false) {
        guard folderCache != nil else { return }
        let start = lock.withLock { () -> Bool in
            if scanningFolders || (!force && Date().timeIntervalSince(foldersListedAt) < Self.folderInterval) { return false }
            scanningFolders = true
            foldersListedAt = Date()
            return true
        }
        guard start else { return }
        artifactQueue.async { [self] in
            rebuildFolders()
            lock.withLock { scanningFolders = false }
        }
    }

    /// Lists the folders now, on the calling thread. A root that cannot be reached keeps the folders it had at the
    /// last look; a root that is no longer in the settings file is forgotten.
    func rebuildFolders() {
        guard let folderCache else { return }
        let roots = ((try? Config.load(from: configFile)) ?? config).folders
        let kept = (try? JSONDecoder().decode([String: [FolderCard]].self, from: Data(contentsOf: folderCache))) ?? [:]
        var listed: [String: [FolderCard]] = [:]
        var all: [FolderCard] = []
        for root in roots where listed[root.path] == nil {
            let found = FolderScanner.scan(root, home: homeDir) ?? kept[root.path] ?? []
            listed[root.path] = found
            all += found
        }
        if listed != kept, let data = try? JSONEncoder().encode(listed) {
            try? FileManager.default.createDirectory(at: folderCache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: folderCache, options: .atomic)
        }
        lock.withLock {
            folderCards = all
            current.folders = all
        }
    }

    /// Builds the cards now, on the calling thread, and replaces the snapshot.
    func rebuild() {
        if let loaded = try? Config.load(from: configFile) { config = loaded }     // a broken file keeps the last good settings
        var sessions = reader.openSessions()
        let gists = gists(for: Set(sessions.map(\.id)))
        for session in sessions where historyFiles[session.id] == nil {
            historyFiles[session.id] = reader.historyFile(for: session.id)
        }
        let open = Set(sessions.map(\.id))
        historyFiles = historyFiles.filter { open.contains($0.key) }
        let replies = replyGists.gists(historyFiles: historyFiles)
        for index in sessions.indices {
            sessions[index].gist = gists[sessions[index].id] ?? []
            sessions[index].replyGist = replies[sessions[index].id] ?? []
            // A session writes to its history file with every message, so the file's time is when it was last used.
            sessions[index].lastActive = historyFiles[sessions[index].id].flatMap {
                (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
            }
        }
        let apps = catalog.apps(aliases: config.appAliases)
        let sites = KnownSites.merged(user: config.sites, apps: apps, folders: KnownFolders.all(home: homeDir))
        lock.withLock {
            current = CardSnapshot(sessions: sessions, artifacts: Self.linked(allArtifacts, to: sessions), apps: apps, sites: sites,
                                   folders: folderCards)
                .takingTitles(fromTabs: tabs)
        }
        writeDebugFile()
    }

    /// The artifact scan has its own queue: the first one reads gigabytes of history and must not hold up the sessions.
    private func refreshArtifacts() {
        guard artifactIndex != nil else { return }
        let start = lock.withLock { () -> Bool in
            if scanningArtifacts { return false }
            scanningArtifacts = true
            return true
        }
        guard start else { return }
        artifactQueue.async { [self] in
            rebuildArtifacts()
            lock.withLock { scanningArtifacts = false }
        }
    }

    /// Scans for artifacts now, on the calling thread, and puts them into the snapshot.
    func rebuildArtifacts() {
        guard let artifactIndex else { return }
        let found = artifactIndex.refresh()
        let openTabs = chromeTabs?() ?? []
        lock.withLock {
            allArtifacts = found
            tabs = openTabs
            current.artifacts = Self.linked(found, to: current.sessions)
            current = current.takingTitles(fromTabs: openTabs)
        }
        writeDebugFile()
    }

    /// Writes what Jarvis knows right now to a local file, so a wrong pick can be traced to what the cards said.
    private func writeDebugFile() {
        guard let debugFile else { return }
        let (snapshot, seenTabs) = lock.withLock { (current, tabs) }
        let dump: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "sessions": snapshot.sessions.map { ["label": $0.label, "folder": $0.folderLabel, "host": $0.host.rawValue, "id": $0.id,
                                                 "typed": $0.gist, "replies": $0.replyGist,
                                                 "lastActive": $0.lastActive.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()] as [String: Any] },
            "artifacts": snapshot.artifacts.map { ["url": $0.url.absoluteString, "title": $0.title ?? NSNull(), "description": $0.description ?? NSNull(),
                                                   "sessions": $0.links.map { ["id": $0.sessionId, "shown": $0.shown] as [String: Any] }] as [String: Any] },
            "tabs": seenTabs.map { ["url": $0.url, "title": $0.title] },
            "folders": snapshot.folders.count,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        try? FileManager.default.createDirectory(at: debugFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: debugFile, options: .atomic)
    }

    /// Only artifacts that an open session published, opened or read become cards. The rest are never offered,
    /// so they are not sent anywhere either.
    private static func linked(_ artifacts: [ArtifactCard], to sessions: [SessionCard]) -> [ArtifactCard] {
        let open = Set(sessions.map(\.id))
        return artifacts.filter { card in card.links.contains { open.contains($0.sessionId) } }
    }

    /// Gists are rebuilt only when the history file or the set of open sessions has changed.
    private func gists(for sessionIds: Set<String>) -> [String: [String]] {
        let history = claudeDir.appendingPathComponent("history.jsonl")
        let attributes = try? FileManager.default.attributesOfItem(atPath: history.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let stamp = "\(modified)|\(size)|\(sessionIds.sorted().joined(separator: ","))"
        if let gistCache, gistCache.stamp == stamp { return gistCache.gists }
        let built = gistBuilder.gists(historyFile: history, for: sessionIds)
        gistCache = (stamp, built)
        return built
    }
}
