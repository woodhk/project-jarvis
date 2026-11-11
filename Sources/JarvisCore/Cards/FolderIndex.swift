import Foundation

/// A folder below one of the roots named in the settings file. It opens in Finder.
public struct FolderCard: Equatable, Sendable, Codable {
    public var name: String
    public var path: String
    /// The names from the root down to this folder's parent. Empty for the root itself.
    public var trail: [String]
    public var depth: Int

    public init(name: String, path: String, trail: [String], depth: Int) {
        self.name = name
        self.path = path
        self.trail = trail
        self.depth = depth
    }
}

/// Lists the folders below a root, by name only. No file is opened or read, and nothing leaves this Mac.
public enum FolderScanner {
    /// Folders that are never worth offering.
    static let ignoredNames: Set<String> = ["node_modules", "__pycache__", "venv", "DerivedData"]
    /// A folder with one of these endings is a single thing to the user (an app, a project file), not a folder to walk into.
    static let packageEndings: Set<String> = ["app", "bundle", "framework", "plugin", "pkg", "xcodeproj", "xcworkspace", "playground", "lproj",
                                              "xcassets", "screenstudio", "photoslibrary", "fcpbundle", "imovielibrary", "tvlibrary",
                                              "musiclibrary", "logicx", "band", "rtfd", "key", "pages", "numbers", "dvr", "drp", "sparsebundle"]

    /// The root and every folder below it down to `root.depth`, nearest first. Nil when the root is not there (a drive
    /// that is not plugged in). Hidden folders, packages and the contents of shortcuts are left out; a folder named in
    /// `root.skip` is listed but not entered.
    public static func scan(_ root: FolderRoot, home: URL = Paths.home, limit: Int = 6000) -> [FolderCard]? {
        let manager = FileManager.default
        let rootURL = root.url(home: home)
        var isFolder: ObjCBool = false
        guard manager.fileExists(atPath: rootURL.path, isDirectory: &isFolder), isFolder.boolValue else { return nil }
        // A root that is there but may not be listed (macOS has not been told to allow it) counts as not there.
        guard (try? manager.contentsOfDirectory(atPath: rootURL.path)) != nil else { return nil }
        let rootName = rootURL.lastPathComponent
        let stayOut = Set(root.skip.map { rootURL.appendingPathComponent($0).standardizedFileURL.path })
        var cards = [FolderCard(name: rootName, path: rootURL.path, trail: [], depth: 0)]
        var waiting: [(url: URL, trail: [String], depth: Int)] = [(rootURL, [rootName], 1)]
        var next = 0
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        while next < waiting.count, cards.count < limit {
            let (folder, trail, depth) = waiting[next]
            next += 1
            guard depth <= root.depth else { continue }
            let entries = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            for entry in entries.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let values = try? entry.resourceValues(forKeys: keys)
                let isShortcut = values?.isSymbolicLink == true
                var leadsToFolder: ObjCBool = false
                let isFolder = isShortcut ? (manager.fileExists(atPath: entry.path, isDirectory: &leadsToFolder) && leadsToFolder.boolValue)
                                          : values?.isDirectory == true
                let name = entry.lastPathComponent
                guard isFolder, values?.isPackage != true, !packageEndings.contains(entry.pathExtension.lowercased()),
                      !ignoredNames.contains(name) else { continue }
                cards.append(FolderCard(name: name, path: entry.path, trail: trail, depth: depth))
                if !isShortcut, !stayOut.contains(entry.standardizedFileURL.path) { waiting.append((entry, trail + [name], depth + 1)) }
                if cards.count >= limit { break }
            }
        }
        return cards
    }
}

/// Finds the folder a phrase means, by the words of its name and of the folders above it. All of it happens on this
/// Mac. A folder is opened outright only when the phrase asks for a folder in so many words ("folder", "in Finder",
/// the drive's name): folder names are also the names of pieces of work, and sessions come first.
public enum FolderMatcher {
    static let cueWords: Set<String> = ["folder", "folders", "directory", "directories", "finder", "drive", "ssd", "disk"]
    /// Said with one of these, the request is for something else.
    static let otherKinds: Set<String> = ["session", "sessions", "terminal", "artifact", "page", "tab", "chat", "website", "app"]
    static let glue: Set<String> = ["the", "my", "a", "an", "in", "on", "of", "from", "inside", "under", "within", "for", "to", "and", "at",
                                    "there", "that", "this", "hard", "external"]
    static let numbers: [String: String] = ["zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
                                            "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12"]

    /// The words of a name or a phrase in one comparable form: lowercase, "&" as "and", letters and digits apart
    /// ("ep09" is "ep", "9"), numbers without leading zeros and never spelled out, small words dropped.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        for word in Normalizer.words(text.replacingOccurrences(of: "&", with: " and ")) {
            var piece = ""
            var pieces: [String] = []
            for character in word {
                if let last = piece.last, last.isNumber != character.isNumber {
                    pieces.append(piece)
                    piece = ""
                }
                piece.append(character)
            }
            if !piece.isEmpty { pieces.append(piece) }
            for piece in pieces {
                if piece.first?.isNumber == true {
                    let trimmed = String(piece.drop(while: { $0 == "0" }))
                    result.append(trimmed.isEmpty ? "0" : trimmed)
                } else if let digits = numbers[piece] {
                    result.append(digits)
                } else if !glue.contains(piece) {
                    result.append(piece)
                }
            }
        }
        return result
    }

    /// Two words are the same word when they are equal, or one is the other with "s" or "es" added ("episode" and
    /// "episodes", "ninas" for Nina's). Anything looser lets "thumbnails" find a folder called "thumb". Numbers
    /// must be equal.
    static func fits(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.first?.isNumber == true || b.first?.isNumber == true { return false }
        let (short, long) = a.count < b.count ? (a, b) : (b, a)
        return long == short + "s" || long == short + "es"
    }

    private struct Found {
        var card: FolderCard
        var unsaid: Int          // words of the folder's name that were not said
        var named: Int           // words said that are in the folder's name
        var exact: Int           // of those, the ones said exactly as they are written
        var whole: Bool          // every word of the folder's name was said exactly
    }

    /// The folders a phrase could mean, best first, and whether it asks for a folder in so many words.
    private static func candidates(_ transcript: String, cards: CardSnapshot) -> (found: [Found], cue: Bool) {
        guard !cards.folders.isEmpty else { return ([], false) }
        let raw = Normalizer.words(transcript)
        guard !raw.contains(where: otherKinds.contains) else { return ([], false) }
        let said = tokens(Normalizer.stripLead(transcript)).filter { !cueWords.contains($0) }
        guard !said.isEmpty else { return ([], false) }
        let rootWords = Set(cards.folders.filter { $0.depth == 0 }.flatMap { tokens($0.name) })
        let cue = raw.contains(where: cueWords.contains) || said.contains(where: rootWords.contains)
        var found: [(index: Int, value: Found)] = []
        for (index, card) in cards.folders.enumerated() {
            let name = tokens(card.name)
            let named = said.filter { word in name.contains { fits(word, $0) } }.count
            guard named > 0 else { continue }
            if named < said.count {
                let above = card.trail.flatMap(tokens)
                guard said.allSatisfy({ word in name.contains { fits(word, $0) } || above.contains { fits(word, $0) } }) else { continue }
            }
            let unsaid = name.filter { word in !said.contains { fits($0, word) } }.count
            let exact = said.filter(name.contains).count
            found.append((index, Found(card: card, unsaid: unsaid, named: named, exact: exact, whole: name.allSatisfy(said.contains))))
        }
        // Best first: the most words said exactly as written, then the least of the name left unsaid, then the
        // folder nearest the top.
        func key(_ entry: (index: Int, value: Found)) -> (Int, Int, Int, Int, Int) {
            (-entry.value.exact, entry.value.unsaid, -entry.value.named, entry.value.card.depth, entry.index)
        }
        found.sort { key($0) < key($1) }
        return (found.map(\.value), cue)
    }

    /// What to do with a phrase that asks for a folder in so many words: open the one folder that fits, or the one
    /// whose whole name was said; offer the best two when it is not that clear. Nil when the phrase does not ask for a
    /// folder or none fits.
    public static func direct(_ transcript: String, cards: CardSnapshot) -> Outcome? {
        let (found, cue) = candidates(transcript, cards: cards)
        guard cue, let best = found.first else { return nil }
        if found.count == 1 { return .open(cards.target(for: best.card)) }
        let whole = found.filter(\.whole)
        if whole.count == 1 { return .open(cards.target(for: whole[0].card)) }
        // The phrase says which folder is wanted, so the choice made is worth remembering.
        return .choices(found.prefix(2).map { cards.target(for: $0.card) }, rememberable: true)
    }

    /// The folder whose whole name, of two words or more, is in the phrase, whether or not it says "folder".
    public static func namedInFull(_ transcript: String, cards: CardSnapshot) -> Target? {
        candidates(transcript, cards: cards).found.first { $0.whole && tokens($0.card.name).count >= 2 }.map { cards.target(for: $0.card) }
    }

    /// The best two folders for a phrase, whether or not it says "folder": for offering when nothing else fits.
    public static func offer(_ transcript: String, cards: CardSnapshot) -> [Target] {
        candidates(transcript, cards: cards).found.prefix(2).map { cards.target(for: $0.card) }
    }
}
