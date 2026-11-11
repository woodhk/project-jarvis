import Foundation
import Testing
@testable import JarvisCore

/// Calls the real Jev service with the fixture cards. Runs only with JARVIS_LIVE=1 and TYPESAFE_API_KEY set.
/// Each raw reply is saved in Fixtures/jev/ as a record of what the service answered.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["JARVIS_LIVE"] == "1"))
struct JevLiveTests {
    let cards: CardSnapshot
    let client = JevClient(key: { ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] },
                           scrubber: Scrubber(userNames: Scrubber.systemUserNames()), timeoutMs: 5000)

    init() throws { cards = try CoreFixture.cards() }

    func ask(_ phrase: String, saveAs name: String) async throws -> JevAnswers {
        let began = Date()
        let (answers, raw) = try await client.askKeepingRaw(transcript: phrase, cards: cards, front: .session(id: "s-front"))
        print("LIVE \(name): \(Int(Date().timeIntervalSince(began) * 1000)) ms; kind \(top(answers.kind)); "
            + "all \(top(answers.sessionAll)); other \(top(answers.sessionOther ?? [:])); artifact \(top(answers.artifact)); "
            + "known \(answers.known); describes \(answers.describes)")
        try raw.write(to: CoreFixture.dir.appendingPathComponent("jev/live-\(name).json"))
        return answers
    }

    func top(_ p: [String: Double]) -> String {
        p.sorted { $0.value > $1.value }.prefix(2).map { "\($0.key.split(separator: "/").last ?? "") \(($0.value * 100).rounded() / 100)" }.joined(separator: ", ")
    }

    func best(_ p: [String: Double]?) -> String? { p?.max { $0.value < $1.value }?.key }

    @Test func phraseOneIsAnArtifactOfTheDiscoverySession() async throws {
        let a = try await ask("For our next Instagram reel video, open the artifact about discovery.", saveAs: "phrase-1")
        #expect(best(a.kind) == "artifact")
        #expect(best(a.sessionOther) == "s-discovery")
    }

    @Test func phraseTwoIsTheShareSession() async throws {
        let a = try await ask("Open the open source insta to comment session.", saveAs: "phrase-2")
        #expect((a.sessionOther?["s-share"] ?? 0) >= 0.80)
    }

    @Test func phraseThreeIsAnArtifactOfTheGifSession() async throws {
        let a = try await ask("Open the artifact for the GIF marking.", saveAs: "phrase-3")
        #expect(best(a.kind) == "artifact")
        #expect((a.sessionOther?["s-gif"] ?? 0) >= 0.80)
    }

    /// A session asked for by a word that is only in its description, not in its name. The yes/no check must not veto it.
    @Test func aSessionKnownOnlyByItsWordsIsStillKnown() async throws {
        let (answers, raw) = try await client.askKeepingRaw(transcript: "Open the hand movement session.", cards: cards, front: .none)
        print("LIVE gist-only: all \(top(answers.sessionAll)); known \(answers.known); describes \(answers.describes)")
        try raw.write(to: CoreFixture.dir.appendingPathComponent("jev/live-gist-only.json"))
        #expect(best(answers.sessionAll) == "s-front")
        #expect(answers.known >= 0.2)
    }
}
