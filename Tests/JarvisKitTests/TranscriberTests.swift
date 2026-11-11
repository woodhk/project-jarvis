import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

// These need the speech model; they are skipped when it has not been downloaded.
let hasModel = FileManager.default.fileExists(atPath: Paths.modelFile.path)

@Suite(.serialized) struct TranscriberTests {
    @Test(.enabled(if: hasModel)) func hearsOpenYouTube() throws {
        let t = try Transcriber(modelPath: Paths.modelFile.path)
        let text = t.transcribe(try Fixture.samples("open-youtube"), hint: "YouTube, ChatGPT")
        #expect(text.lowercased().filter(\.isLetter) == "openyoutube")
    }

    @Test(.enabled(if: hasModel)) func aVeryShortClipDoesNotFail() throws {
        let t = try Transcriber(modelPath: Paths.modelFile.path)
        _ = t.transcribe([Float](repeating: 0, count: 6400), hint: "")   // 0.4 s: must return, whatever the text
    }

    @Test(.enabled(if: hasModel)) func theHintFixesAProjectWord() throws {
        let t = try Transcriber(modelPath: Paths.modelFile.path)
        let text = t.transcribe(try Fixture.samples("open-source-insta"), hint: "insta comment, open source")
        #expect(text.lowercased().contains("insta"))
    }

    @Test func aMissingModelIsAnError() {
        #expect(throws: (any Error).self) { _ = try Transcriber(modelPath: "/nonexistent/model.bin") }
    }

    @Test func aModelThatIsNotThereGivesNoTextAndDoesNotHang() {
        let lazy = LazyTranscriber(modelPath: "/nonexistent/model.bin")
        #expect(lazy.transcribe(FakeRecorder.tone, hint: "") == "")
        #expect(!lazy.isReady)
    }

    /// Quitting Jarvis produced a crash report: the speech library stops the program at exit when a model is still loaded.
    @Test(.enabled(if: hasModel)) func theProgramExitsCleanlyAfterUsingTheSpeechModel() throws {
        let binary = Fixture.dir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/Jarvis")
        try #require(FileManager.default.fileExists(atPath: binary.path))
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--transcribe", Fixture.dir.appendingPathComponent("open-youtube.wav").path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).lowercased().contains("youtube"))
    }
}
