import Foundation
import Testing
@testable import JarvisCore

func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // The temporary folder is reached through a symlink (/var → /private/var); return the real path so comparisons hold.
    guard let real = realpath(dir.path, nil) else { return dir }
    defer { free(real) }
    return URL(fileURLWithPath: String(cString: real), isDirectory: true)
}

@Suite struct ConfigTests {
    @Test func defaultConfigIsWrittenOnce() throws {
        let file = try tempDir().appendingPathComponent("sub/config.json")
        #expect(try Config.load(from: file) == Config.default)
        #expect(FileManager.default.fileExists(atPath: file.path))

        var edited = Config.default
        edited.sites.append(SiteCard(name: "Canva", aliases: [], url: URL(string: "https://www.canva.com/")!))
        try JSONEncoder().encode(edited).write(to: file)
        #expect(try Config.load(from: file).sites.map(\.name) == ["YouTube", "Gemini", "Canva"])
    }

    @Test func theDefaultsAreTheAgreedStartingValues() {
        let t = Config.default.thresholds
        #expect(t.openAt == 0.80)
        #expect(t.jevTimeoutMs == 800)          // 600 at first; one of 11 real requests took 618 ms and fell back
        #expect(t.tapMs == 300)
        #expect(t.choiceTimeoutS == 8)
        #expect(Config.default.sites.map(\.url.absoluteString) == ["https://www.youtube.com/", "https://gemini.google.com/app"])
        #expect(Config.default.appAliases == ["vs code": "Visual Studio Code"])
        #expect(Config.default.hintWords == ["ChatGPT", "Claude", "ExpressVPN"])       // the apps the user named; spelled for the speech recogniser
    }

    @Test func aHandEditedFileMayLeaveThingsOut() throws {
        let file = try tempDir().appendingPathComponent("config.json")
        try Data(#"{"sites":[{"name":"Canva","url":"https://www.canva.com/"}],"thresholds":{"openAt":0.9}}"#.utf8).write(to: file)
        let config = try Config.load(from: file)
        #expect(config.sites == [SiteCard(name: "Canva", aliases: [], url: URL(string: "https://www.canva.com/")!)])
        #expect(config.thresholds.openAt == 0.9)
        #expect(config.thresholds.jevTimeoutMs == 800)
        #expect(config.appAliases == [:])
        #expect(config.hintWords == Config.default.hintWords)
    }

    @Test func aBrokenFileIsAnErrorAndIsNotOverwritten() throws {
        let file = try tempDir().appendingPathComponent("config.json")
        try Data("{ not json".utf8).write(to: file)
        #expect(throws: (any Error).self) { _ = try Config.load(from: file) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ not json")
    }
}
