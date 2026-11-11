import Foundation

/// The numbers that decide when to open, when to ask and when to give up. Starting values; tuned in the acceptance test.
public struct Thresholds: Codable, Equatable, Sendable {
    public var openAt = 0.80
    public var knownFloor = 0.20
    public var describesFloor = 0.50
    public var artifactShare = 0.60
    /// An artifact request may open directly only when the sessions that have an artifact hold at least this share
    /// of Jev's answer. Between `artifactAskFloor` and this, the pages are offered. Below `artifactAskFloor`, the
    /// request is about something that is not a card, and nothing happens.
    public var artifactSessionFloor = 0.50
    public var artifactAskFloor = 0.20
    /// When Jev's question about pages gives at least this much to a page other than the one its question about
    /// sessions leads to, the two answers disagree, and both pages are offered instead of one being opened.
    public var pageMajority = 0.50
    public var recentGapS = 600.0
    public var jevTimeoutMs = 800
    public var tapMs = 300
    public var choiceTimeoutS = 8
    /// How long the list of all sessions waits for a number. Longer than two choices: there is more to read.
    public var listTimeoutS = 20

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Thresholds()
        openAt = try c.decodeIfPresent(Double.self, forKey: .openAt) ?? d.openAt
        knownFloor = try c.decodeIfPresent(Double.self, forKey: .knownFloor) ?? d.knownFloor
        describesFloor = try c.decodeIfPresent(Double.self, forKey: .describesFloor) ?? d.describesFloor
        artifactShare = try c.decodeIfPresent(Double.self, forKey: .artifactShare) ?? d.artifactShare
        artifactSessionFloor = try c.decodeIfPresent(Double.self, forKey: .artifactSessionFloor) ?? d.artifactSessionFloor
        artifactAskFloor = try c.decodeIfPresent(Double.self, forKey: .artifactAskFloor) ?? d.artifactAskFloor
        pageMajority = try c.decodeIfPresent(Double.self, forKey: .pageMajority) ?? d.pageMajority
        recentGapS = try c.decodeIfPresent(Double.self, forKey: .recentGapS) ?? d.recentGapS
        jevTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .jevTimeoutMs) ?? d.jevTimeoutMs
        tapMs = try c.decodeIfPresent(Int.self, forKey: .tapMs) ?? d.tapMs
        choiceTimeoutS = try c.decodeIfPresent(Int.self, forKey: .choiceTimeoutS) ?? d.choiceTimeoutS
        listTimeoutS = try c.decodeIfPresent(Int.self, forKey: .listTimeoutS) ?? d.listTimeoutS
    }
}

/// A folder whose subfolders can be opened in Finder by name: an external drive, a projects folder.
public struct FolderRoot: Codable, Equatable, Sendable {
    /// A full path, or one that starts with "~/".
    public var path: String
    /// How many levels below the root are listed.
    public var depth: Int
    /// Folders, relative to the root, that are listed but not entered.
    public var skip: [String]

    public init(path: String, depth: Int = 4, skip: [String] = []) {
        self.path = path
        self.depth = depth
        self.skip = skip
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        depth = try c.decodeIfPresent(Int.self, forKey: .depth) ?? 4
        skip = try c.decodeIfPresent([String].self, forKey: .skip) ?? []
    }

    public func url(home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true) }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// The file the user edits: websites, extra names for apps, and thresholds.
public struct Config: Codable, Equatable, Sendable {
    public var sites: [SiteCard]
    /// A spoken name → the app's real name, for example "vs code" → "Visual Studio Code".
    public var appAliases: [String: String]
    public var thresholds: Thresholds
    /// Names the speech recogniser should know how to spell even when the app is not running, such as "ChatGPT".
    public var hintWords: [String]
    /// Folders whose subfolders can be opened in Finder by name.
    public var folders: [FolderRoot]

    public init(sites: [SiteCard], appAliases: [String: String], thresholds: Thresholds, hintWords: [String] = Config.defaultHintWords,
                folders: [FolderRoot] = []) {
        self.sites = sites
        self.appAliases = appAliases
        self.thresholds = thresholds
        self.hintWords = hintWords
        self.folders = folders
    }

    public static let defaultHintWords = ["ChatGPT", "Claude", "ExpressVPN"]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sites = try c.decodeIfPresent([SiteCard].self, forKey: .sites) ?? []
        appAliases = try c.decodeIfPresent([String: String].self, forKey: .appAliases) ?? [:]
        thresholds = try c.decodeIfPresent(Thresholds.self, forKey: .thresholds) ?? Thresholds()
        hintWords = try c.decodeIfPresent([String].self, forKey: .hintWords) ?? Config.defaultHintWords
        folders = try c.decodeIfPresent([FolderRoot].self, forKey: .folders) ?? []
    }

    public static let `default` = Config(
        sites: [SiteCard(name: "YouTube", aliases: ["you tube"], url: URL(string: "https://www.youtube.com/")!),
                SiteCard(name: "Gemini", aliases: [], url: URL(string: "https://gemini.google.com/app")!)],
        appAliases: ["vs code": "Visual Studio Code"],
        thresholds: Thresholds())

    /// Reads the file, writing the default one first when none exists. A file that cannot be read as JSON is an error and is left as it is.
    public static func load(from file: URL) throws -> Config {
        let manager = FileManager.default
        if !manager.fileExists(atPath: file.path) {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(Config.default).write(to: file, options: .atomic)
        }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: file))
    }
}
