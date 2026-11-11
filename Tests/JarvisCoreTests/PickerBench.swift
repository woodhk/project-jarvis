import Foundation
import Testing
@testable import JarvisCore

/// Answers with a scripted reply, or throws, and counts how often it was asked.
final class FakeJev: JevAsking, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: JevAnswers
    private var error: JevError?
    private var asked = 0
    private var warmed = 0
    private var fronts: [FrontCard] = []

    init(answers: JevAnswers, error: JevError?) {
        self.answers = answers
        self.error = error
    }

    var calls: Int { lock.lock(); defer { lock.unlock() }; return asked }
    var warmCalls: Int { lock.lock(); defer { lock.unlock() }; return warmed }
    var lastFront: FrontCard? { lock.lock(); defer { lock.unlock() }; return fronts.last }

    func ask(transcript: String, cards: CardSnapshot, front: FrontCard) async throws -> JevAnswers {
        let (reply, failure) = lock.withLock { () -> (JevAnswers, JevError?) in
            asked += 1
            fronts.append(front)
            return (answers, error)
        }
        if let failure { throw failure }
        return reply
    }

    func warm() { lock.lock(); warmed += 1; lock.unlock() }
}

final class TraceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var traces: [PickTrace] = []
    func add(_ trace: PickTrace) { lock.lock(); traces.append(trace); lock.unlock() }
    var last: PickTrace? { lock.lock(); defer { lock.unlock() }; return traces.last }
}

/// The acceptance cards plus helpers to build a picker over a scripted Jev.
struct PickerBench {
    var cards: CardSnapshot
    let idle = PickContext(front: .none, choosing: false)
    let choosing = PickContext(front: .none, choosing: true)
    let traces = TraceBox()

    init() throws { cards = try CoreFixture.cards() }

    func front(_ id: String) -> PickContext { PickContext(front: .session(id: id), choosing: false) }

    func session(_ id: String) -> SessionCard { cards.sessions.first { $0.id == id }! }
    func target(_ id: String) -> Target { cards.target(for: session(id)) }

    func make(kind: String = "session", session: [String: Double] = [:], other: [String: Double]? = nil,
              artifact: [String: Double] = [:], known: Double = 1, describes: Double = 1, error: JevError? = nil,
              remembered: [String: String] = [:], thresholds: Thresholds = Thresholds()) -> (Picker, FakeJev, RememberedStore) {
        let jev = FakeJev(answers: JevAnswers(kind: [kind: 1], sessionAll: session, sessionOther: other, artifact: artifact,
                                              known: known, describes: describes), error: error)
        let store = RememberedStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-remembered-\(UUID().uuidString).json"))
        for (phrase, key) in remembered { store.remember(phrase, cardKey: key) }
        let traces = self.traces
        return (Picker(jev: jev, remembered: store, thresholds: thresholds, trace: { traces.add($0) }), jev, store)
    }
}

extension PickerBench {
    static let artifactBase = "https://claude.ai/artifact/"

    func artifact(_ name: String) -> ArtifactCard { cards.artifacts.first { $0.url.lastPathComponent == name }! }
    func artifactTarget(_ name: String) -> Target { cards.target(for: artifact(name)) }
    func frontArtifact(_ name: String) -> PickContext { PickContext(front: .artifact(url: artifact(name).url), choosing: false) }
}
