import Foundation

/// Jev's answers for one spoken phrase, mapped back from option names to card identifiers.
public struct JevAnswers: Equatable, Sendable {
    /// Keys "session", "artifact", "app_or_website".
    public var kind: [String: Double]
    /// Session id → probability, over every open session.
    public var sessionAll: [String: Double]
    /// The same question without the session in front; nil when it was not asked.
    public var sessionOther: [String: Double]?
    /// Artifact link → probability; empty when there are no artifact cards.
    public var artifact: [String: Double]
    public var known: Double
    public var describes: Double

    public init(kind: [String: Double], sessionAll: [String: Double], sessionOther: [String: Double]?, artifact: [String: Double],
                known: Double, describes: Double) {
        self.kind = kind
        self.sessionAll = sessionAll
        self.sessionOther = sessionOther
        self.artifact = artifact
        self.known = known
        self.describes = describes
    }
}

public enum JevError: Error, Equatable {
    case noKey
    case timeout
    /// The HTTP status, or 0 when the service could not be reached at all.
    case http(Int)
    case malformed
}

public protocol JevAsking: Sendable {
    func ask(transcript: String, cards: CardSnapshot, front: FrontCard) async throws -> JevAnswers
    /// Opens the connection early, so the request that follows is quick.
    func warm()
}

/// Talks to TypeSafe's Jev over HTTPS. One request per phrase, with a hard time limit.
public struct JevClient: JevAsking {
    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let modelsEndpoint = URL(string: "https://api.typesafe.ai/v1/models")!

    /// A connection stays open for a while after use, so warming again sooner than this gains nothing.
    static let warmInterval: TimeInterval = 20

    private let key: @Sendable () -> String?
    private let scrubber: Scrubber
    private let timeoutMs: Int
    private let session: URLSession
    private let lastContact = LastContact()

    private final class LastContact: @unchecked Sendable {
        private let lock = NSLock()
        private var at = Date.distantPast
        /// Records a contact now. Returns false when the previous one was less than `interval` ago.
        func mark(ifOlderThan interval: TimeInterval) -> Bool {
            lock.withLock {
                guard Date().timeIntervalSince(at) >= interval else { return false }
                at = Date()
                return true
            }
        }
    }

    public init(key: @escaping @Sendable () -> String?, scrubber: Scrubber, timeoutMs: Int, session: URLSession = .shared) {
        self.key = key
        self.scrubber = scrubber
        self.timeoutMs = timeoutMs
        self.session = session
    }

    public func ask(transcript: String, cards: CardSnapshot, front: FrontCard) async throws -> JevAnswers {
        try await askKeepingRaw(transcript: transcript, cards: cards, front: front).answers
    }

    func askKeepingRaw(transcript: String, cards: CardSnapshot, front: FrontCard) async throws -> (answers: JevAnswers, raw: Data) {
        guard let key = key(), !key.isEmpty else { throw JevError.noKey }
        let built = JevRequestBuilder.build(transcript: transcript, cards: cards, front: front, scrubber: scrubber)
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = built.body
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = lastContact.mark(ifOlderThan: 0)
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw JevError.malformed }
        guard http.statusCode == 200 else { throw JevError.http(http.statusCode) }
        return (try Self.parse(data, built: built), data)
    }

    public func warm() {
        // Without a key Jarvis works on this Mac alone: there is no request to prepare for, so nothing is contacted.
        guard let key = key(), !key.isEmpty else { return }
        guard lastContact.mark(ifOlderThan: Self.warmInterval) else { return }
        var request = URLRequest(url: Self.modelsEndpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: request).resume()
    }

    /// The request, raced against the time limit. Whichever finishes first decides; the other is cancelled.
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let session = self.session
        let limit = UInt64(max(1, timeoutMs)) * 1_000_000
        return try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                do {
                    return try await session.data(for: request)
                } catch let error as URLError where error.code == .timedOut || error.code == .cancelled {
                    throw JevError.timeout
                } catch is CancellationError {
                    throw JevError.timeout
                } catch {
                    throw JevError.http(0)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: limit)
                throw JevError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw JevError.timeout }
            return first
        }
    }

    static func parse(_ data: Data, built: JevRequestBuilder.Built) throws -> JevAnswers {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: Any],
              let kind = probabilities(answers["kind"]), !kind.isEmpty else { throw JevError.malformed }

        func mapped(_ name: String, through ids: [String: String]) -> [String: Double]? {
            guard let byName = probabilities(answers[name]) else { return nil }
            var byId: [String: Double] = [:]
            for (option, probability) in byName {
                if let id = ids[option] { byId[id] = probability }
            }
            return byId
        }
        func noul(_ name: String) -> Double {
            ((answers[name] as? [String: Any])?["noul"] as? NSNumber)?.doubleValue ?? 1
        }
        return JevAnswers(kind: kind,
                          sessionAll: mapped("session_all", through: built.sessionIds) ?? [:],
                          sessionOther: mapped("session_other", through: built.sessionIds),
                          artifact: mapped("artifact", through: built.artifactURLs) ?? [:],
                          known: noul("known"), describes: noul("describes"))
    }

    private static func probabilities(_ answer: Any?) -> [String: Double]? {
        guard let raw = (answer as? [String: Any])?["probabilities"] as? [String: Any] else { return nil }
        return raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }
}
