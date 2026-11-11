import Foundation
import Testing
@testable import JarvisCore

/// Folders under a root the user names in the settings file (an external drive, say) can be opened in Finder by
/// name: "open the Claude Code Series folder", "open episode 9 in the Claude Code Series folder".
@Suite struct FolderIndexTests {
    var b: PickerBench
    var cards: CardSnapshot
    static let root = "/Volumes/vault"

    static func folder(_ relative: String) -> FolderCard {
        let parts = relative.isEmpty ? [] : relative.split(separator: "/").map(String.init)
        return FolderCard(name: parts.last ?? "vault", path: relative.isEmpty ? root : root + "/" + relative,
                          trail: parts.isEmpty ? [] : ["vault"] + parts.dropLast(), depth: parts.count)
    }

    static let tree = ["", "Brand", "Brand/Videos", "Brand/Videos/Claude Code Series", "Brand/Videos/Claude Code Series/Episodes",
                       "Brand/Videos/Claude Code Series/Episodes/01 Claude Code", "Brand/Videos/Claude Code Series/Episodes/09 Plugins",
                       "Brand/Videos/Claude Code Series/Episodes/11 Hooks", "Brand/Videos/Claude Code Series/Shorts & Reels",
                       "Brand/Videos/Claude Code Series/Shorts & Reels/Shenzhen-insights-2", "Brand/Videos/Pipeline",
                       "Brand/Videos/Pipeline/ep09-plugins", "Brand/Videos/Pipeline/ep10-hooks", "Brand/Motion", "Brand/Motion/discovery-reel",
                       "Brand/Motion/hooks-ep11", "Brand/Motion/shenzhen-insights-2", "Brand/Client streams", "Brand/Client streams/nina",
                       "Brand/Library", "Brand/Library/Photos of me", "Brand/Library/Sound", "Brand/References", "Brand/References/Motion reels",
                       // Seen on the real drive: a folder called "hook", one called "thumb", and one name in two places.
                       "Brand/Motion/shenzhen-insights-2/hook", "Brand/Library/Thumbnails", "Brand/Videos/Pipeline/ep09-plugins/thumb",
                       "Brand/Library/Thumbnails/Client streams"]

    init() throws {
        b = try PickerBench()
        cards = b.cards
        cards.folders = Self.tree.map(Self.folder)
    }

    func target(_ relative: String) -> Target { cards.target(for: Self.folder(relative)) }

    @Test func aFolderIsShownWithWhereItIs() {
        #expect(target("Brand/Videos/Claude Code Series") == Target(
            destination: .folder(path: "/Volumes/vault/Brand/Videos/Claude Code Series"), title: "Claude Code Series",
            subtitle: "Finder · vault › Brand › Videos", cardKey: "folder:/Volumes/vault/Brand/Videos/Claude Code Series"))
        #expect(target("").subtitle == "Finder")
        #expect(target("").title == "vault")
    }

    @Test(arguments: [("open the Claude Code Series folder", "Brand/Videos/Claude Code Series"),
                      ("can you open my Claude Code series folder in Finder", "Brand/Videos/Claude Code Series"),
                      ("open Claude Code Series in Finder", "Brand/Videos/Claude Code Series"),
                      ("open the episodes folder in the Claude Code Series", "Brand/Videos/Claude Code Series/Episodes"),
                      ("open episode 9 in the Claude Code Series folder", "Brand/Videos/Claude Code Series/Episodes/09 Plugins"),
                      ("open the episode nine folder", "Brand/Videos/Claude Code Series/Episodes/09 Plugins"),
                      ("open the plugins episode folder", "Brand/Videos/Claude Code Series/Episodes/09 Plugins"),
                      ("open the hooks episode folder", "Brand/Videos/Claude Code Series/Episodes/11 Hooks"),
                      ("open the shorts and reels folder", "Brand/Videos/Claude Code Series/Shorts & Reels"),
                      ("open the photos of me folder", "Brand/Library/Photos of me"),
                      ("open Nina's folder", "Brand/Client streams/nina"),
                      ("open the discovery reel folder", "Brand/Motion/discovery-reel"),
                      ("open the motion folder", "Brand/Motion"),
                      ("open motion on the vault", "Brand/Motion"),
                      ("open the thumbnails folder", "Brand/Library/Thumbnails"),
                      ("open the sound folder on my SSD", "Brand/Library/Sound"),
                      ("open the vault", ""), ("open vault in Finder", "")])
    func aFolderAskedForAsAFolderOpens(_ phrase: String, _ relative: String) async {
        let (p, jev, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: phrase, cards: cards, context: b.idle) == .open(target(relative)))
        #expect(jev.calls == 0)
    }

    // Several folders fit and none is named in full: the two best are offered, the one with the least left unsaid first.
    @Test func foldersThatFitEquallyAreOffered() async {
        let (p, jev, _) = b.make()
        #expect(await p.pick(transcript: "open the hooks folder", cards: cards, context: b.idle)
            == .choices([target("Brand/Videos/Claude Code Series/Episodes/11 Hooks"), target("Brand/Motion/hooks-ep11")], rememberable: true))
        // The same name in two places: both are named in full, so it is a question too. The one nearer the top comes first.
        #expect(await p.pick(transcript: "open the shenzhen insights 2 folder", cards: cards, context: b.idle)
            == .choices([target("Brand/Motion/shenzhen-insights-2"), target("Brand/Videos/Claude Code Series/Shorts & Reels/Shenzhen-insights-2")],
                        rememberable: true))
        #expect(await p.pick(transcript: "open the client streams directory", cards: cards, context: b.idle)
            == .choices([target("Brand/Client streams"), target("Brand/Library/Thumbnails/Client streams")], rememberable: true))
        #expect(jev.calls == 0)
        // The choice is remembered, so the same words go straight there the next time.
        let (q, _, store) = b.make()
        store.remember("open the hooks folder", cardKey: target("Brand/Motion/hooks-ep11").cardKey)
        #expect(await q.pick(transcript: "open the hooks folder", cards: cards, context: b.idle) == .open(target("Brand/Motion/hooks-ep11")))
    }

    // Folder names on the drive are also the names of pieces of work, and sessions come first. Without the word
    // "folder" (or "in Finder", or the drive's name) a folder is never opened outright.
    @Test func withoutSayingFolderSessionsComeFirst() async {
        let (p, jev, _) = b.make(kind: "session", session: ["s-discovery": 0.95, "s-gif": 0.05])
        #expect(await p.pick(transcript: "open discovery reel", cards: cards, context: b.idle) == .open(b.target("s-discovery")))
        #expect(jev.calls == 1)
        #expect(FolderMatcher.direct("open discovery reel", cards: cards) == nil)
        #expect(FolderMatcher.direct("open motion", cards: cards) == nil)
        #expect(FolderMatcher.direct("open Claude Code Series", cards: cards) == nil)
    }

    // …but when nothing else fits, the folder is offered, and a choice made is remembered.
    @Test func aFolderIsOfferedWhenNothingElseFits() async {
        let (p, _, store) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "open Claude Code Series", cards: cards, context: b.idle)
            == .choices([target("Brand/Videos/Claude Code Series"), target("Brand/Videos/Claude Code Series/Episodes/01 Claude Code")],
                        rememberable: true))
        let (q, _, _) = b.make(kind: "session", session: ["s-gif": 0.5, "s-ideas": 0.5], known: 0.05)
        #expect(await q.pick(transcript: "open photos of me", cards: cards, context: b.idle)
            == .choices([target("Brand/Library/Photos of me")], rememberable: true))
        store.remember("open Claude Code Series", cardKey: target("Brand/Videos/Claude Code Series").cardKey)
        #expect(await p.pick(transcript: "open Claude Code Series", cards: cards, context: b.idle) == .open(target("Brand/Videos/Claude Code Series")))
    }

    // "Open Claude Code Series", said without "folder", used to open the Claude app: its name is one word of the
    // sentence. A folder whose whole name was said is the better reading, so both are offered, the folder first.
    @Test func aFolderNamedInFullIsOfferedBeforeAnAppThatIsOneWordOfIt() async {
        var with = cards
        let claude = AppCard(name: "Claude", aliases: [], path: "/Applications/Claude.app")
        with.apps.append(claude)
        let (p, _, _) = b.make(kind: "app_or_website")
        #expect(await p.pick(transcript: "open Claude Code Series", cards: with, context: b.idle)
            == .choices([target("Brand/Videos/Claude Code Series"), with.target(for: claude)], rememberable: true))
        #expect(await p.pick(transcript: "open Claude", cards: with, context: b.idle) == .open(with.target(for: claude)))
        #expect(await p.pick(transcript: "can you get Claude up for me", cards: with, context: b.idle) == .open(with.target(for: claude)))
    }

    @Test func onlyAPluralOrAPossessiveCountsAsTheSameWord() {
        #expect(FolderMatcher.fits("episode", "episodes"))
        #expect(FolderMatcher.fits("ninas", "nina"))
        #expect(FolderMatcher.fits("boxes", "box"))
        #expect(!FolderMatcher.fits("thumbnails", "thumb"))
        #expect(!FolderMatcher.fits("hooks", "hooked"))
        #expect(!FolderMatcher.fits("1", "11"))
        #expect(!FolderMatcher.fits("9", "9s"))
    }

    @Test(arguments: ["open the tax return folder", "open the pattern reel folder session", "open the folder", "open the artifact folder page",
                      "type in gigocran", "open the insta comment dm folder"])
    func aPhraseThatFitsNoFolderIsLeftToTheRest(_ phrase: String) {
        #expect(FolderMatcher.direct(phrase, cards: cards) == nil)
        #expect(FolderMatcher.offer(phrase, cards: cards).isEmpty)
    }

    @Test func namesAreComparedWordByWord() {
        #expect(FolderMatcher.tokens("Shorts & Reels") == ["shorts", "reels"])
        #expect(FolderMatcher.tokens("ep09-plugins") == ["ep", "9", "plugins"])
        #expect(FolderMatcher.tokens("09 Plugins") == ["9", "plugins"])
        #expect(FolderMatcher.tokens("Photos of me") == ["photos", "me"])
        #expect(FolderMatcher.tokens("episode nine in the Claude Code series") == ["episode", "9", "claude", "code", "series"])
        #expect(FolderMatcher.tokens("B-roll (mine)") == ["b", "roll", "mine"])
        #expect(FolderMatcher.tokens("00 Intro") == ["0", "intro"])
    }

    @Test func oldCardFilesAndSettingsStillLoad() throws {
        let data = try JSONEncoder().encode(b.cards)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["folders"] = nil
        let decoded = try JSONDecoder().decode(CardSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.folders.isEmpty)
        #expect(decoded.sessions.count == b.cards.sessions.count)
        let settings = try JSONDecoder().decode(Config.self, from: Data(#"{"sites": [], "folders": [{"path": "/Volumes/vault"}, {"path": "~/Work", "depth": 2, "skip": ["old"]}]}"#.utf8))
        #expect(settings.folders == [FolderRoot(path: "/Volumes/vault", depth: 4, skip: []), FolderRoot(path: "~/Work", depth: 2, skip: ["old"])])
        #expect(try JSONDecoder().decode(Config.self, from: Data(#"{"sites": []}"#.utf8)).folders.isEmpty)
    }
}

@Suite struct FolderScannerTests {
    /// root/Brand/Videos/Series/Episodes/09 Plugins, with things around it that must not become cards.
    func makeTree() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-folders-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("drive", isDirectory: true)
        let manager = FileManager.default
        for path in ["Brand/Videos/Series/Episodes/09 Plugins/deep/deeper", "Brand/.hidden/inside", "Brand/node_modules/pkg",
                     "Brand/Recording.screenstudio/inner", "Keys/Backup/private", "Apps/Thing.app/Contents", "Empty"] {
            try manager.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try Data("x".utf8).write(to: root.appendingPathComponent("Brand/notes.txt"))
        try manager.createDirectory(at: base.appendingPathComponent("elsewhere/target/child"), withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: root.appendingPathComponent("Brand/Shortcut"), withDestinationURL: base.appendingPathComponent("elsewhere/target"))
        guard let real = realpath(root.path, nil) else { return root }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    @Test func foldersAreListedDownToTheDepthAndNothingElse() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let found = try #require(FolderScanner.scan(FolderRoot(path: root.path, depth: 5, skip: ["Keys/Backup"])))
        let names = Set(found.map { $0.path.replacingOccurrences(of: root.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/")) })
        #expect(names == ["", "Brand", "Brand/Videos", "Brand/Videos/Series", "Brand/Videos/Series/Episodes", "Brand/Videos/Series/Episodes/09 Plugins",
                          "Brand/Shortcut", "Keys", "Keys/Backup", "Apps", "Empty"])
        // Not listed: hidden folders, node_modules, what is inside a package or a shortcut, what is below the depth,
        // files, and what is inside a folder the settings say to stay out of (the folder itself is listed).
        let plugins = try #require(found.first { $0.name == "09 Plugins" })
        #expect(plugins.trail == ["drive", "Brand", "Videos", "Series", "Episodes"])
        #expect(plugins.depth == 5)
        #expect(found.first { $0.depth == 0 }?.name == "drive")
        #expect(found.first { $0.depth == 0 }?.trail == [])
    }

    @Test func aRootThatIsNotThereGivesNothing() {
        #expect(FolderScanner.scan(FolderRoot(path: "/nonexistent/jarvis-\(UUID().uuidString)", depth: 3, skip: [])) == nil)
    }

    // macOS can refuse to list a drive (the permission was not given yet). That is "not reachable", not "empty":
    // otherwise the folders known from the last look would be thrown away.
    @Test func aRootThatCannotBeReadGivesNothing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-locked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("inside"), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        #expect(FolderScanner.scan(FolderRoot(path: root.path, depth: 3, skip: [])) == nil)
    }

    @Test func aRootMayStartAtTheHomeFolder() {
        #expect(FolderRoot(path: "~/Work", depth: 2, skip: []).url(home: URL(fileURLWithPath: "/Users/sam")).path == "/Users/sam/Work")
        #expect(FolderRoot(path: "/Volumes/vault", depth: 2, skip: []).url(home: URL(fileURLWithPath: "/Users/sam")).path == "/Volumes/vault")
    }
}
