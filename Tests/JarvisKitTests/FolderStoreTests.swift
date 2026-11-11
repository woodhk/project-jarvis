import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

/// Folders below the roots in the settings file become cards. The list is kept on this Mac, so a drive that is
/// unplugged is still known by name and Jarvis can say that it is not there.
@Suite struct FolderStoreTests {
    func store(_ root: URL) -> CardStore {
        CardStore(configFile: root.appendingPathComponent("config.json"), claudeDir: Fixture.coreDir.appendingPathComponent("claude"),
                  homeDir: root, inspector: TableInspector(), catalog: AppCatalog(roots: [], extras: []), userNames: [],
                  folderCache: root.appendingPathComponent("folder-index.json"))
    }

    @Test func foldersBelowARootBecomeCardsAndOutliveAnUnpluggedDrive() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let drive = root.appendingPathComponent("drive", isDirectory: true)
        try FileManager.default.createDirectory(at: drive.appendingPathComponent("Brand/Videos"), withIntermediateDirectories: true)
        try Data(#"{"sites": [], "folders": [{"path": "~/drive", "depth": 3}]}"#.utf8).write(to: root.appendingPathComponent("config.json"))

        let first = store(root)
        #expect(first.snapshot.folders.isEmpty)
        first.rebuildFolders()
        #expect(first.snapshot.folders.map(\.name) == ["drive", "Brand", "Videos"])
        first.rebuild()                                              // the other cards are rebuilt: the folders stay
        #expect(first.snapshot.folders.map(\.name) == ["drive", "Brand", "Videos"])
        #expect(first.snapshot.folders.last?.path == drive.appendingPathComponent("Brand/Videos").path)

        // Unplugged, and Jarvis started again: the names are still known.
        try FileManager.default.removeItem(at: drive)
        let second = store(root)
        second.rebuildFolders()
        #expect(second.snapshot.folders.map(\.name) == ["drive", "Brand", "Videos"])

        // A root taken out of the settings file is forgotten, on disk too.
        try Data(#"{"sites": []}"#.utf8).write(to: root.appendingPathComponent("config.json"))
        second.rebuildFolders()
        #expect(second.snapshot.folders.isEmpty)
        let third = store(root)
        third.rebuildFolders()
        #expect(third.snapshot.folders.isEmpty)
    }

    @Test @MainActor func aFolderOnAnUnpluggedDriveSaysSoAndStaysRemembered() async {
        let folder = Target(destination: .folder(path: "/Volumes/vault/Brand/Videos"), title: "Videos", subtitle: "Finder · vault › Brand",
                            cardKey: "folder:/Volumes/vault/Brand/Videos")
        let k = Kit(heard: "open the videos folder", outcome: .open(folder))
        k.remembered.remember("open the videos folder", cardKey: folder.cardKey)
        k.opener.error = .gone
        await k.hold()
        #expect(k.pill.last == .nothing(heard: "open the videos folder", message: PillCopy.folderGone))
        #expect(k.remembered.cardKey(for: "open the videos folder") == folder.cardKey)      // the drive will be back
        #expect(k.logged.last?.outcome == "gone")
    }
}
