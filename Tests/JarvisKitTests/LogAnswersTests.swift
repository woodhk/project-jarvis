import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

/// The log line of a request keeps what Jev answered, so a wrong pick can be explained afterwards.
@MainActor @Suite struct LogAnswersTests {
    @Test func theLogLineKeepsJevsAnswers() async {
        let kit = Kit(heard: "open youtube")
        let answers: [String: [String: Double]] = ["kind": ["session": 0.9, "artifact": 0.1], "session_all": ["pattern-reel": 0.7]]
        kit.trace = PickTrace(step: "jev", kind: "session", top: ["pattern-reel": 0.7], answers: answers)
        await kit.hold()
        #expect(kit.logged.last?.jev == answers)
    }

    @Test func aLogLineWithoutJevHasNoAnswerField() async throws {
        let kit = Kit(heard: "open youtube")
        kit.trace = PickTrace(step: "name")
        await kit.hold()
        #expect(kit.logged.last?.jev == nil)
        #expect(try String(contentsOf: kit.logFile, encoding: .utf8).contains("\"jev\"") == false)
    }
}
