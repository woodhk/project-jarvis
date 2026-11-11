import Foundation

/// How one pick was reached, for the log and for tuning.
public struct PickTrace: Equatable, Sendable {
    /// control, remembered, name, jev, front or fallback.
    public var step: String
    public var kind: String?
    public var known: Double?
    /// The two most probable candidates, by title.
    public var top: [String: Double]
    /// Everything Jev answered, by question and then by title: "kind", "session_all", "session_other", "artifact"
    /// and "yes_no" (known, describes). Empty when Jev was not asked or did not answer.
    public var answers: [String: [String: Double]]

    public init(step: String, kind: String? = nil, known: Double? = nil, top: [String: Double] = [:],
                answers: [String: [String: Double]] = [:]) {
        self.step = step
        self.kind = kind
        self.known = known
        self.top = top
        self.answers = answers
    }
}

/// Decides what a spoken phrase means. It never opens a guess: below the threshold it offers two choices,
/// and when nothing matches it says so.
public struct Picker: Picking {
    private let jev: JevAsking
    private let remembered: RememberedStore
    private let thresholds: Thresholds
    private let trace: (@Sendable (PickTrace) -> Void)?

    public init(jev: JevAsking, remembered: RememberedStore, thresholds: Thresholds, trace: (@Sendable (PickTrace) -> Void)? = nil) {
        self.jev = jev
        self.remembered = remembered
        self.thresholds = thresholds
        self.trace = trace
    }

    public func prepare() {
        jev.warm()
    }

    public func pick(transcript: String, cards: CardSnapshot, context: PickContext) async -> Outcome {
        // 1. Control words.
        let words = Normalizer.words(transcript)
        if words == ["back"] || words == ["go", "back"] { return done(.back, PickTrace(step: "control")) }
        if context.choosing, let index = Self.choiceIndex(words) { return done(.pickChoice(index), PickTrace(step: "control")) }
        if context.choosing, Self.saysYes(words) { return done(.pickChoice(0), PickTrace(step: "control")) }
        if context.choosing, Self.saysNo(words) { return done(.cancel, PickTrace(step: "control")) }
        if Self.asksForList(words) { return done(.list(Self.listTargets(cards)), PickTrace(step: "control")) }
        // "Close Spotify", "quit Spotify". Decided here, before anything that could open: such a phrase never opens.
        if let outcome = Self.appRequest(words, in: cards) { return done(outcome, PickTrace(step: "control")) }

        // 2. A phrase the user has already settled. A phrase with no word of its own ("open the artifact") is never
        // remembered and never looked up: its meaning depends on what is in front.
        let bare = FallbackMatcher.contentWords(transcript).isEmpty
        if let key = remembered.cardKey(for: transcript) {
            if !bare, let target = Self.target(forKey: key, in: cards) { return done(.open(target), PickTrace(step: "remembered")) }
            remembered.forget(transcript)
        }

        // 3. An app or website named outright.
        if let target = NameMatcher(apps: cards.apps, sites: cards.sites).match(transcript) {
            return done(.open(target), PickTrace(step: "name"))
        }
        // A folder asked for as a folder ("open the Claude Code Series folder", "… in Finder").
        if let outcome = FolderMatcher.direct(transcript, cards: cards) { return done(outcome, PickTrace(step: "folder")) }
        // When nothing else fits in the end, a folder that fits is offered, never opened.
        func orFolders(_ outcome: Outcome) -> Outcome {
            guard outcome == .nothing || outcome == .unknownName else { return outcome }
            let folders = FolderMatcher.offer(transcript, cards: cards)
            return folders.isEmpty ? outcome : .choices(folders, rememberable: !bare)
        }
        // A short phrase that is nearly a name ("chat GBT" for ChatGPT) is the name, misheard.
        let stripped = Normalizer.words(Normalizer.stripLead(transcript))
        if stripped.count <= 3, let target = Self.nearestName(to: stripped, in: cards) {
            return done(.open(target), PickTrace(step: "name"))
        }

        // 4. Jev. 6. If it does not answer, a local match that is only ever offered.
        guard let answers = try? await jev.ask(transcript: transcript, cards: cards, front: context.front) else {
            let pages = FallbackMatcher.asksForPage(transcript) ? FallbackMatcher.rankPages(transcript, cards: cards) : []
            let ranked = pages.isEmpty ? FallbackMatcher.rank(transcript, cards: cards) : pages
            let outcome: Outcome = ranked.isEmpty ? .nothing : .choices(Array(ranked.prefix(2)), rememberable: false)
            return done(orFolders(outcome), PickTrace(step: "fallback"))
        }

        // 5. Rules applied to Jev's answer. A choice may be remembered only when the phrase says which thing is meant.
        let said = Self.said(answers, in: cards)
        func answered(_ outcome: Outcome, _ trace: PickTrace) -> Outcome {
            var trace = trace
            trace.answers = said
            return done(orFolders(outcome), trace)
        }
        let rememberable = !bare && answers.describes >= thresholds.describesFloor
        let kind = answers.kind.max { $0.value < $1.value }?.key ?? "session"
        switch kind {
        case "app_or_website":
            let target = Self.nearestName(inside: stripped, in: cards)
            // An app or website that is one word of the sentence, and a folder whose whole name is the sentence
            // ("open Claude Code Series"): the folder is the better reading, but it was not asked for as a folder,
            // so both are offered.
            if let target, let folder = FolderMatcher.namedInFull(transcript, cards: cards) {
                return answered(.choices([folder, target], rememberable: !bare), PickTrace(step: "jev", kind: kind, known: answers.known))
            }
            return answered(target.map(Outcome.open) ?? .unknownName, PickTrace(step: "jev", kind: kind, known: answers.known))
        case "artifact":
            let (outcome, trace) = artifactRequest(answers, cards: cards, context: context, rememberable: rememberable, bare: bare)
            return answered(outcome, trace)
        default:
            if bare, let (outcome, trace) = sessionBehindFrontArtifact(answers, cards: cards, context: context) {
                return answered(outcome, trace)
            }
            // The session already in front is never the answer to a request for a session. Jev is asked a second
            // question without it; when that question could not be asked (two sessions open), it is taken out here.
            var probabilities = answers.sessionOther ?? answers.sessionAll
            if answers.sessionOther == nil, case .session(let frontId) = context.front { probabilities[frontId] = nil }
            let ranked = Self.rank(probabilities, in: cards)
            let trace = PickTrace(step: "jev", kind: kind, known: answers.known, top: Self.top(ranked))
            guard answers.known >= thresholds.knownFloor else { return answered(.nothing, trace) }
            return answered(decide(ranked.map { (cards.target(for: $0.card), $0.probability) }, rememberable: rememberable), trace)
        }
    }

    /// A request for an artifact. Only sessions that have an artifact are candidates; the page is then chosen within the session.
    /// `bare` is true when the phrase has no word of its own ("open the artifact"): only then does what is in front
    /// decide. Whether a phrase names something is read from its words; Jev's yes/no on that proved unsteady
    /// ("can you open the gif artifact?" came out as "does not say which").
    private func artifactRequest(_ answers: JevAnswers, cards: CardSnapshot, context: PickContext, rememberable: Bool,
                                 bare: Bool) -> (Outcome, PickTrace) {
        // "Open the artifact", said with a session in front: that session's own artifact.
        if bare, case .session(let id) = context.front,
           let own = cards.artifacts(of: id).first {
            return (.open(cards.target(for: own)), PickTrace(step: "front", kind: "artifact", known: answers.known))
        }
        let candidates = Set(cards.sessions.filter { !cards.artifacts(of: $0.id).isEmpty }.map(\.id))
        // A session in front that has no artifact cannot be meant, but it is where the user has just been typing, so
        // it draws the answer to itself. When Jev was also asked without it, that answer is the one to use.
        var base = answers.sessionAll
        if case .session(let frontId) = context.front, !candidates.contains(frontId), let other = answers.sessionOther { base = other }
        let limited = base.filter { candidates.contains($0.key) }
        let sum = limited.values.reduce(0, +)
        let whole = base.values.reduce(0, +)
        let share = whole > 0 ? sum / whole : 0
        // How much of the answer points at sessions that have an artifact decides what may happen:
        // very little, and the request is about something that is not a card (scaling up the rest would turn a few
        // per cent into a sure open); a middling share, and the pages are offered; most of it, and the best may open.
        guard sum > 0, share >= thresholds.artifactAskFloor else {
            return (.nothing, PickTrace(step: "jev", kind: "artifact", known: answers.known, top: Self.top(Self.rank(base, in: cards))))
        }
        let mayOpen = share >= thresholds.artifactSessionFloor
        let ranked = Self.rank(limited.mapValues { $0 / sum }, in: cards)
        let trace = PickTrace(step: "jev", kind: "artifact", known: answers.known, top: Self.top(ranked))
        guard answers.known >= thresholds.knownFloor, let best = ranked.first else { return (.nothing, trace) }

        // Jev was also asked directly which page is meant. When it is sure of a page that has a title or description
        // of its own, and that page's session is at least a plausible answer, the page opens.
        let named = cards.artifacts.filter { $0.title != nil || $0.description != nil }
        func pageProbability(_ card: ArtifactCard) -> Double { answers.artifact[card.url.absoluteString] ?? 0 }
        if let sure = named.max(by: { pageProbability($0) < pageProbability($1) }), pageProbability(sure) >= thresholds.openAt,
           ranked.contains(where: { candidate in candidate.probability >= 0.2 && sure.links.contains { $0.sessionId == candidate.card.id } }) {
            let target = cards.target(for: sure)
            return (.open(target), PickTrace(step: "jev", kind: "artifact", known: answers.known,
                                             top: [target.title: (pageProbability(sure) * 100).rounded() / 100]))
        }

        func page(of session: SessionCard) -> Target {
            let list = cards.artifacts(of: session.id)
            let shares = list.map { answers.artifact[$0.url.absoluteString] ?? 0 }
            let total = shares.reduce(0, +)
            if list.count > 1, total > 0, let top = shares.indices.max(by: { shares[$0] < shares[$1] }),
               shares[top] / total >= thresholds.artifactShare {
                return cards.target(for: list[top])
            }
            return cards.target(for: list[0])
        }
        // The two questions can disagree. The session question follows where artifacts are talked about; the page
        // question follows the pages' own titles. When the page question gives most of its answer to a page other than
        // the one the session answer leads to, and that one has a title too (so it was judged fairly), neither answer
        // is sure: both pages are offered, the page question's first.
        let sessionPage = page(of: best.card)
        if let preferred = named.max(by: { pageProbability($0) < pageProbability($1) }), pageProbability(preferred) >= thresholds.pageMajority,
           cards.target(for: preferred) != sessionPage,
           named.contains(where: { cards.target(for: $0) == sessionPage }) {
            return (.choices([cards.target(for: preferred), sessionPage], rememberable: rememberable), trace)
        }
        if mayOpen, best.probability >= thresholds.openAt { return (.open(sessionPage), trace) }
        var offered: [Target] = []
        for candidate in ranked.prefix(2) {
            let target = page(of: candidate.card)
            if !offered.contains(target) { offered.append(target) }
        }
        // Two sessions that lead to the same page are one answer, not a question.
        if mayOpen, offered.count == 1, ranked.count > 1, ranked.prefix(2).map(\.probability).reduce(0, +) >= thresholds.openAt {
            return (.open(offered[0]), trace)
        }
        return (.choices(offered, rememberable: rememberable), trace)
    }

    /// "Open the terminal for this", said with an artifact in front: the open session that last published or opened it.
    private func sessionBehindFrontArtifact(_ answers: JevAnswers, cards: CardSnapshot, context: PickContext) -> (Outcome, PickTrace)? {
        guard case .artifact(let url) = context.front else { return nil }
        let linked = cards.openSessions(linkedTo: url)
        guard let latest = linked.first else { return nil }
        let trace = PickTrace(step: "front", kind: "session", known: answers.known)
        if linked.count == 1 || latest.at.timeIntervalSince(linked[1].at) >= thresholds.recentGapS {
            return (.open(cards.target(for: latest.session)), trace)
        }
        return (.choices([cards.target(for: latest.session), cards.target(for: linked[1].session)], rememberable: false), trace)
    }

    /// Open when the best candidate is sure enough; otherwise offer the best two.
    func decide(_ ranked: [(target: Target, probability: Double)], rememberable: Bool) -> Outcome {
        guard let best = ranked.first else { return .nothing }
        if best.probability >= thresholds.openAt { return .open(best.target) }
        return .choices(ranked.prefix(2).map(\.target), rememberable: rememberable)
    }

    /// The words for each number that can be said to choose from a list. "One" is not among them: it is also an
    /// everyday word ("the second one"), so it counts only when no other number is said.
    private static let numberWords: [Set<String>] = [
        ["first", "1", "1st"], ["two", "second", "2", "2nd"], ["three", "third", "3", "3rd"], ["four", "fourth", "4", "4th"],
        ["five", "fifth", "5", "5th"], ["six", "sixth", "6", "6th"], ["seven", "seventh", "7", "7th"],
        ["eight", "eighth", "8", "8th"], ["nine", "ninth", "9", "9th"],
    ]

    /// Which choice a short spoken answer means: "two", "the second one", "number 4"; "one", "the first one".
    /// "To" and "too" count as "two", and "for" as "four", only when they are the whole answer. Longer sentences,
    /// and answers that name two different numbers, are new requests.
    static func choiceIndex(_ words: [String]) -> Int? {
        if words == ["to"] || words == ["too"] { return 1 }
        if words == ["for"] { return 3 }
        guard !words.isEmpty, words.count <= 4 else { return nil }
        let said = numberWords.indices.filter { index in words.contains { numberWords[index].contains($0) } }
        if said.count == 1 { return said[0] }
        if said.isEmpty, words.contains("one") { return 0 }
        return nil
    }

    private static let actionVerbs: [String: AppAction] = ["close": .hide, "hide": .hide, "quit": .quit, "exit": .quit]
    /// Small talk that may come before the verb: "oh, and then can you close Spotify".
    private static let actionLeadIns: Set<String> = [
        "oh", "and", "then", "can", "could", "would", "will", "you", "we", "please", "now", "ok", "okay", "also", "just", "no", "sorry",
        "actually", "hey", "jarvis", "um", "uh", "so", "i", "want", "to", "lets", "go", "ahead", "yeah", "yes", "right", "well", "alright",
    ]
    private static let actionNameEndings: Set<String> = ["app", "application", "please", "now", "window", "windows", "for", "me", "too", "thanks"]

    /// The action and the words that name the app, when the phrase is a request to close or quit: the verb comes
    /// first, after nothing but small talk. "Open the close rates session" is not one.
    static func appVerb(_ words: [String]) -> (action: AppAction, name: [String])? {
        guard let at = words.firstIndex(where: { actionVerbs[$0] != nil }), let action = actionVerbs[words[at]],
              words[..<at].allSatisfy(actionLeadIns.contains) else { return nil }
        var name = Array(words[(at + 1)...])
        while let first = name.first, first == "the" || first == "my" { name.removeFirst() }
        while name.count > 1, let last = name.last, actionNameEndings.contains(last) { name.removeLast() }
        return (action, name)
    }

    /// What a request to close or quit means, or nil when the phrase is not one. Only an app can be closed or quit,
    /// and only by its name. A quit is asked about first when the name was not heard exactly, or when the app holds
    /// Claude Code sessions that would end with it.
    static func appRequest(_ words: [String], in cards: CardSnapshot) -> Outcome? {
        guard let (action, name) = appVerb(words) else { return nil }
        if [["it"], ["this"], ["that"], ["this", "one"], ["that", "one"]].contains(name) { return .appInFront(action) }
        guard !name.isEmpty, name.count <= 5 else { return .appUnknown(action) }
        let spoken = name.joined()
        var exact = true
        var found = cards.apps.first { app in ([app.name] + app.aliases).contains { Normalizer.compact($0) == spoken } }
        if found == nil {
            exact = false
            found = nearestApp(to: Array(spoken), in: cards)
        }
        guard let app = found else { return .appUnknown(action) }
        var ask: AppRequest.Ask?
        if action == .quit {
            let inside = AppRequest.sessionsInside(appNamed: app.name, cards: cards)
            ask = inside > 0 ? .endsSessions(inside) : (exact ? nil : .unsureOfName)
        }
        return .app(AppRequest(action: action, target: cards.target(for: app), ask: ask))
    }

    /// The app whose name is closest to what was said, by the same measure as `nearestName`.
    private static func nearestApp(to spoken: [Character], in cards: CardSnapshot) -> AppCard? {
        var best: (distance: Int, app: AppCard)?
        for app in cards.apps {
            for name in [app.name] + app.aliases {
                let letters = Array(Normalizer.compact(name))
                guard let distance = slip(spoken, letters) else { continue }
                if best == nil || distance < best!.distance { best = (distance, app) }
            }
        }
        return best?.app
    }

    private static let yesAnswers: Set<String> = ["yes", "yeah", "yep", "yup", "sure", "okay", "ok", "confirm", "doit", "goahead", "yesplease",
                                                  "yesdoit", "yesgoahead"]
    private static let noAnswers: Set<String> = ["no", "nope", "cancel", "nevermind", "dont", "nothanks", "nothankyou", "stop", "neither", "none"]

    /// True when the whole answer is a yes: it takes what is on show.
    static func saysYes(_ words: [String]) -> Bool {
        words.count <= 3 && yesAnswers.contains(words.joined())
    }

    /// True when the whole answer is a no. "No, the artifact in Chrome" is not one: that is a correction.
    static func saysNo(_ words: [String]) -> Bool {
        words.count <= 3 && noAnswers.contains(words.joined())
    }

    /// The most sessions a list shows: one for each number key.
    static let listLimit = 9
    private static let listFillers: Set<String> = [
        "show", "me", "list", "all", "the", "my", "of", "open", "current", "currently", "running", "claude", "code", "terminal",
        "terminals", "session", "sessions", "what", "whats", "is", "are", "everything", "that", "i", "have", "can", "could", "you",
        "please", "which", "up", "bring", "options", "choices", "see", "let", "to", "in", "active", "there", "give", "a", "your", "our", "again",
    ]

    /// True when the phrase asks to see every open session ("show all sessions", "list my terminals", "what's open")
    /// and names none of them: a single word about one piece of work makes it an ordinary request.
    static func asksForList(_ words: [String]) -> Bool {
        guard !words.isEmpty, words.count <= 12, words.allSatisfy(listFillers.contains) else { return false }
        let said = Set(words)
        if !said.isDisjoint(with: ["sessions", "terminals", "everything", "options", "choices"]) { return true }
        if said.contains("list"), words.count > 1 { return true }
        if said.contains("all"), !said.isDisjoint(with: ["show", "list", "see"]) { return true }
        return !said.isDisjoint(with: ["what", "whats"]) && !said.isDisjoint(with: ["open", "running"])
    }

    /// Every open session, the one used most recently first, at most `listLimit` of them.
    static func listTargets(_ cards: CardSnapshot) -> [Target] {
        cards.sessions.enumerated().sorted { a, b in
            switch (a.element.lastActive, b.element.lastActive) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.prefix(listLimit).map { cards.target(for: $0.element) }
    }

    private func done(_ outcome: Outcome, _ trace: PickTrace) -> Outcome {
        self.trace?(trace)
        return outcome
    }

    /// Jev's answers with titles in place of identifiers, rounded, for the log.
    static func said(_ answers: JevAnswers, in cards: CardSnapshot) -> [String: [String: Double]] {
        func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        func bySession(_ probabilities: [String: Double]) -> [String: Double] {
            var result: [String: Double] = [:]
            for card in cards.sessions {
                if let probability = probabilities[card.id] { result[card.label, default: 0] += rounded(probability) }
            }
            return result
        }
        var result: [String: [String: Double]] = [
            "kind": answers.kind.mapValues(rounded),
            "yes_no": ["known": rounded(answers.known), "describes": rounded(answers.describes)],
        ]
        if !answers.sessionAll.isEmpty { result["session_all"] = bySession(answers.sessionAll) }
        if let other = answers.sessionOther { result["session_other"] = bySession(other) }
        if !answers.artifact.isEmpty {
            var pages: [String: Double] = [:]
            for card in cards.artifacts {
                if let probability = answers.artifact[card.url.absoluteString] { pages[cards.target(for: card).title, default: 0] += rounded(probability) }
            }
            result["artifact"] = pages
        }
        return result
    }

    /// Open sessions with their probabilities, most probable first. Answers for sessions that are no longer open are dropped.
    static func rank(_ probabilities: [String: Double], in cards: CardSnapshot) -> [(card: SessionCard, probability: Double)] {
        cards.sessions.enumerated()
            .compactMap { index, card in probabilities[card.id].map { (index: index, card: card, probability: $0) } }
            .sorted { ($0.probability, $1.index) > ($1.probability, $0.index) }
            .map { ($0.card, $0.probability) }
    }

    static func top(_ ranked: [(card: SessionCard, probability: Double)]) -> [String: Double] {
        Dictionary(ranked.prefix(2).map { ($0.card.label, ($0.probability * 100).rounded() / 100) }, uniquingKeysWith: { first, _ in first })
    }

    /// The card a remembered key points to, if it still exists.
    static func target(forKey key: String, in cards: CardSnapshot) -> Target? {
        if let session = cards.sessions.first(where: { "session:\($0.id)" == key }) { return cards.target(for: session) }
        if let site = cards.sites.first(where: { "site:\($0.name)" == key }) { return cards.target(for: site) }
        if let app = cards.apps.first(where: { "app:\($0.path)" == key }) { return cards.target(for: app) }
        if let artifact = cards.artifacts.first(where: { "artifact:\($0.url.absoluteString)" == key }) { return cards.target(for: artifact) }
        if let folder = cards.folders.first(where: { "folder:\($0.path)" == key }) { return cards.target(for: folder) }
        return nil
    }

    /// The app or website whose name is closest to these words taken together, when it is close enough for its
    /// length (one wrong letter for a short name, two for a name of six letters or more).
    static func nearestName(to words: [String], in cards: CardSnapshot) -> Target? {
        nearest(to: Array(words.joined()), in: cards)?.target
    }

    /// The same, looking at every run of one to three words: "chat gbt in the desktop" contains "chat gbt".
    /// Of two names that fit equally well, the longer stretch of the sentence wins: "Google Chrome", not "Google".
    static func nearestName(inside words: [String], in cards: CardSnapshot) -> Target? {
        var best: (distance: Int, letters: Int, target: Target)?
        for length in 1...3 where length <= words.count {
            for start in 0...(words.count - length) {
                let spoken = Array(words[start..<start + length].joined())
                guard let found = nearest(to: spoken, in: cards) else { continue }
                if best == nil || (found.distance, -spoken.count) < (best!.distance, -best!.letters) {
                    best = (found.distance, spoken.count, found.target)
                }
            }
        }
        return best?.target
    }

    /// How far what was said is from a name, when it is near enough to be that name misheard: at most two letters
    /// wrong, at most one in three, and at most one letter longer or shorter. Nil when it is another word
    /// ("find" is not "FindMy").
    static func slip(_ spoken: [Character], _ name: [Character]) -> Int? {
        if spoken == name { return 0 }
        guard abs(spoken.count - name.count) <= 1 else { return nil }
        let distance = editDistance(spoken, name)
        return distance <= 2 && distance * 3 <= name.count ? distance : nil
    }

    private static func nearest(to spoken: [Character], in cards: CardSnapshot) -> (distance: Int, target: Target)? {
        guard !spoken.isEmpty else { return nil }
        var best: (distance: Int, target: Target)?
        func consider(_ names: [String], _ target: Target, exactOnly: Bool = false) {
            for name in names {
                let letters = Array(Normalizer.compact(name))
                guard let distance = slip(spoken, letters), !exactOnly || distance == 0 else { continue }
                if best == nil || distance < best!.distance { best = (distance, target) }
            }
        }
        // A built-in website must be heard exactly. There are many of them, and a near miss ("motion" for Notion)
        // is more likely to be a word about the user's work than a misheard website.
        for site in cards.sites { consider([site.name] + site.aliases, cards.target(for: site), exactOnly: site.builtIn) }
        for app in cards.apps { consider([app.name] + app.aliases, cards.target(for: app)) }
        return best
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1] + [Int](repeating: 0, count: b.count)
            for (j, y) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
