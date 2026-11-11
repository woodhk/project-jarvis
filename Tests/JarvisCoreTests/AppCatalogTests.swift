import Foundation
import Testing
@testable import JarvisCore

@Suite struct AppCatalogTests {
    @Test func catalogListsAppsInRoots() throws {
        let root = try tempDir()
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("A.app"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent("Sub/B.app"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        let missing = root.appendingPathComponent("no-such-folder")

        let apps = AppCatalog(roots: [root, missing], extras: []).apps(aliases: ["the a": "a", "bee": "B"])
        #expect(apps == [AppCard(name: "A", aliases: ["the a"], path: root.appendingPathComponent("A.app").path)])
    }

    @Test func theFirstRootWinsForARepeatedName() throws {
        let first = try tempDir(), second = try tempDir()
        for root in [first, second] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Notes.app"), withIntermediateDirectories: true)
        }
        let apps = AppCatalog(roots: [first, second], extras: []).apps(aliases: [:])
        #expect(apps.map(\.path) == [first.appendingPathComponent("Notes.app").path])
    }

    // From the hand test: "open Chrome" was not understood; only "Google Chrome" worked.
    @Test func anAppIsAlsoKnownWithoutItsMakersName() throws {
        let root = try tempDir()
        for name in ["Google Chrome.app", "Microsoft Excel.app", "Adobe Photoshop 2026.app", "Notes.app", "Google.app"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let apps = AppCatalog(roots: [root], extras: []).apps(aliases: [:])
        #expect(apps.first { $0.name == "Google Chrome" }?.aliases == ["Chrome"])
        #expect(apps.first { $0.name == "Microsoft Excel" }?.aliases == ["Excel"])
        #expect(apps.first { $0.name == "Adobe Photoshop 2026" }?.aliases == ["Photoshop 2026"])
        #expect(apps.first { $0.name == "Notes" }?.aliases == [])
        #expect(apps.first { $0.name == "Google" }?.aliases == [])
        let matcher = NameMatcher(apps: apps, sites: [])
        #expect(matcher.match("open Chrome")?.title == "Google Chrome")
        #expect(Picker.nearestName(to: ["crime"], in: CardSnapshot(apps: apps))?.title == "Google Chrome")     // as the speech model first wrote it
    }

    // Finder does not live in an Applications folder, so it is named on its own.
    @Test func finderIsAnAppEvenThoughItLivesElsewhere() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("core/Finder.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("apps/Notes.app"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = AppCatalog(roots: [root.appendingPathComponent("apps")],
                                 extras: [root.appendingPathComponent("core/Finder.app"), root.appendingPathComponent("core/Missing.app")])
        #expect(catalog.apps(aliases: [:]).map(\.name) == ["Finder", "Notes"])
        #expect(AppCatalog.defaultExtras.map(\.path) == ["/System/Library/CoreServices/Finder.app"])
    }
}
