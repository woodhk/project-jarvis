import Foundation
import Testing
@testable import JarvisCore

/// A wrong pick can only be explained when the log says what Jev answered to every question, not just the top two sessions.
@Suite struct PickTraceTests {
    var b: PickerBench
    static let base = PickerBench.artifactBase

    init() throws { b = try PickerBench() }

    @Test func theTraceCarriesEveryAnswerByTitle() async {
        let (p, _, _) = b.make(kind: "artifact", session: ["s-gif": 0.604, "s-discovery": 0.396], other: ["s-discovery": 1],
                               artifact: [Self.base + "fixture-gif": 0.93, Self.base + "fixture-discovery": 0.07], known: 0.91, describes: 0.84)
        _ = await p.pick(transcript: "open the reaction gif library artifact", cards: b.cards, context: b.idle)
        let answers = b.traces.last?.answers ?? [:]
        #expect(answers["kind"] == ["artifact": 1])
        #expect(answers["session_all"] == ["Emotion-tagged GIF library": 0.6, "discovery-reel": 0.4])
        #expect(answers["session_other"] == ["discovery-reel": 1])
        #expect(answers["artifact"] == ["Reaction GIF Library": 0.93, "Artifact": 0.07])
        #expect(answers["yes_no"] == ["known": 0.91, "describes": 0.84])
    }

    @Test func aPickWithoutJevHasNoAnswers() async {
        let (p, _, _) = b.make(error: .timeout)
        _ = await p.pick(transcript: "open the gif library session", cards: b.cards, context: b.idle)
        #expect(b.traces.last?.answers.isEmpty == true)
        let (q, _, _) = b.make()
        _ = await q.pick(transcript: "back", cards: b.cards, context: b.idle)
        #expect(b.traces.last?.answers.isEmpty == true)
    }
}
