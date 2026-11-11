import Foundation
import Testing
@testable import JarvisCore

/// Answers every request made through a session built by `StubProtocol.session(...)`, without any network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Reply { var status = 200; var body = Data(); var delay: TimeInterval = 0 }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var seen: [String: [URLRequest]] = [:]

    static func session(_ reply: Reply) -> (session: URLSession, id: String) {
        let id = UUID().uuidString
        lock.lock(); replies[id] = reply; lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Stub": id]
        return (URLSession(configuration: configuration), id)
    }

    static func requests(_ id: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return seen[id] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Stub") ?? ""
        Self.lock.lock()
        Self.seen[id, default: []].append(request)
        let reply = Self.replies[id] ?? Reply(status: 500)
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

@Suite struct JevClientTests {
    let cards: CardSnapshot
    let scrub = Scrubber(userNames: ["sam"])

    init() throws { cards = try CoreFixture.cards() }

    func client(_ reply: StubProtocol.Reply, key: String? = "test-key", timeoutMs: Int = 600) -> (JevClient, String) {
        let (session, id) = StubProtocol.session(reply)
        return (JevClient(key: { key }, scrubber: scrub, timeoutMs: timeoutMs, session: session), id)
    }

    @Test func answersMapBackToIds() async throws {
        let body = try Data(contentsOf: CoreFixture.dir.appendingPathComponent("jev/answer-share.json"))
        let (jev, id) = client(.init(body: body))
        let a = try await jev.ask(transcript: "open the open source insta to comment session", cards: cards, front: .session(id: "s-front"))
        #expect(a.sessionAll["s-share"] == 0.98)
        #expect(a.sessionOther?["s-share"] == 0.97)
        #expect((a.kind["session"] ?? 0) > 0.9)
        #expect(a.known == 0.87)
        #expect(a.describes == 0.93)
        #expect(a.artifact["https://claude.ai/artifact/fixture-gif"] == 0.6)
        let sent = try #require(StubProtocol.requests(id).first)
        #expect(sent.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    @Test func missingYesNoAnswersReadAsOne() async throws {
        let (jev, _) = client(.init(body: Data(#"{"answers":{"kind":{"choice":"session","probabilities":{"session":1}}}}"#.utf8)))
        let a = try await jev.ask(transcript: "x", cards: cards, front: .none)
        #expect(a.known == 1)
        #expect(a.describes == 1)
        #expect(a.sessionAll.isEmpty)
        #expect(a.sessionOther == nil)
    }

    @Test func failuresAreNamed() async {
        let (unauthorised, _) = client(.init(status: 401, body: Data("{}".utf8)))
        await #expect(throws: JevError.http(401)) { _ = try await unauthorised.ask(transcript: "x", cards: cards, front: .none) }

        let (slow, _) = client(.init(body: Data("{}".utf8), delay: 2), timeoutMs: 100)
        let began = Date()
        await #expect(throws: JevError.timeout) { _ = try await slow.ask(transcript: "x", cards: cards, front: .none) }
        #expect(Date().timeIntervalSince(began) < 1)

        let (garbled, _) = client(.init(body: Data("oops".utf8)))
        await #expect(throws: JevError.malformed) { _ = try await garbled.ask(transcript: "x", cards: cards, front: .none) }

        let (empty, _) = client(.init(body: Data(#"{"answers":{}}"#.utf8)))
        await #expect(throws: JevError.malformed) { _ = try await empty.ask(transcript: "x", cards: cards, front: .none) }

        let (keyless, id) = client(.init(body: Data("{}".utf8)), key: nil)
        await #expect(throws: JevError.noKey) { _ = try await keyless.ask(transcript: "x", cards: cards, front: .none) }
        #expect(StubProtocol.requests(id).isEmpty)
    }

    /// fn is also a modifier key (fn+arrow), so the key goes down far more often than a request is made.
    @Test func warmingIsNotRepeatedWithinAFewSeconds() async throws {
        let (jev, id) = client(.init(body: Data("{}".utf8)))
        jev.warm()
        jev.warm()
        jev.warm()
        try await Task.sleep(nanoseconds: 200_000_000)
        let seen = StubProtocol.requests(id)
        #expect(seen.count == 1)
        #expect(seen.first?.url?.absoluteString == "https://api.typesafe.ai/v1/models")
        #expect(seen.first?.httpMethod == "GET")
    }

    /// Without a key Jarvis works on this Mac alone, so even the warm-up stays silent.
    @Test func withoutAKeyWarmingContactsNothing() async throws {
        let (keyless, id) = client(.init(body: Data("{}".utf8)), key: nil)
        keyless.warm()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(StubProtocol.requests(id).isEmpty)
    }
}
