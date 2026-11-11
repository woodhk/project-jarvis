import Foundation
import JarvisCore

/// Runs work after a delay. The app uses real time; tests move time by hand.
@MainActor public protocol Scheduling: AnyObject {
    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void)
}

@MainActor public final class MainScheduler: Scheduling {
    public init() {}

    public func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            work()
        }
    }
}

/// Turns hold events into a request: record, transcribe, pick, open, and tell the pill what happened.
@MainActor public final class Coordinator {
    public static let pillDelay: TimeInterval = 0.15
    public static let hintTime: TimeInterval = 1.5
    public static let resultTime: TimeInterval = 3
    /// How long a request waits to learn what was in front. The read starts when the key goes down and normally
    /// finishes while the user speaks; an app that does not answer must not hold the request.
    public static let frontWait: TimeInterval = 0.4
    /// While two choices show: a hold shorter than this means "the second one". Held longer, the pill turns to
    /// "Listening" and the hold is a new request.
    public static let askAgainAfter: TimeInterval = 0.9

    private let recorder: Recording
    private let transcriber: Transcribing
    private let picker: Picking
    private let opener: Opening
    private let front: FrontReading
    private let cards: CardProviding
    private let pill: PillShowing
    private let log: EventLog
    private let thresholds: Thresholds
    private let scheduler: Scheduling
    private let hintWords: @MainActor () -> [String]
    private let lastTrace: @Sendable () -> PickTrace?
    private let remembered: RememberedStore?
    private let appControl: AppControlling?

    /// Goes up with every key event. A result that arrives for an older request is dropped, and old timers do nothing.
    private var request = 0
    private var holding = false
    /// What was in front when the key went down. Read while the user speaks.
    private var frontTask: Task<FrontState, Never>?
    /// The last open, kept briefly so that a desktop switch it causes can be timed.
    private var lastOpen: (released: Date, heard: String, title: String)?
    /// How long the microphone took to start on the last key press. Speech in that time is lost, so it is logged.
    private var micStartMs = 0
    /// Where the user was before the last open: where "back" goes.
    private var backDestination: Destination?

    /// The request before this one, kept briefly so that a correction ("no, the artifact") can lean on it.
    private var earlier: (heard: String, at: Date, opened: Bool)?

    /// Choices on show, waiting for an answer: the two best guesses, or (`full`) the list of every open session.
    private struct Offer {
        var heard: String
        var targets: [Target]
        var rememberable: Bool
        /// True for the list of all sessions. Nothing in it is a guess, so a tap or a silent hold picks nothing:
        /// only a number does, typed or spoken.
        var full = false
        /// Set when the one choice on show is a question ("Quit Terminal?"): saying yes does this, and opens nothing.
        var question: (action: AppAction, why: String)?
    }
    private var offer: Offer?
    /// Goes up whenever the wait for an answer starts again or ends, so an older countdown does nothing.
    private var offerEpoch = 0

    /// One request on its way from the release of the key to its result.
    private struct Run {
        var heard = ""
        var ms: [String: Int] = [:]
        var released = Date()
        var request: Int
        var front = FrontState(card: .none, destination: nil)
        var step: String?
        var sound: [String: Int]?
        var raw: String?
        /// True when this request was understood together with the one before it.
        var followsEarlier = false
    }

    public init(recorder: Recording, transcriber: Transcribing, picker: Picking, opener: Opening, front: FrontReading,
                cards: CardProviding, pill: PillShowing, log: EventLog, thresholds: Thresholds,
                scheduler: Scheduling? = nil, hintWords: @escaping @MainActor () -> [String] = { [] },
                lastTrace: @escaping @Sendable () -> PickTrace? = { nil }, remembered: RememberedStore? = nil,
                appControl: AppControlling? = nil) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.picker = picker
        self.opener = opener
        self.front = front
        self.cards = cards
        self.pill = pill
        self.log = log
        self.thresholds = thresholds
        self.scheduler = scheduler ?? MainScheduler()
        self.hintWords = hintWords
        self.lastTrace = lastTrace
        self.remembered = remembered
        self.appControl = appControl
    }

    /// Call when macOS reports that the active desktop changed. The first change within two seconds of an open
    /// is logged with the time since the key was released.
    public func spaceChanged() {
        guard let open = lastOpen else { return }
        lastOpen = nil
        let ms = Self.elapsed(since: open.released)
        guard ms <= 2000 else { return }
        log.write(EventRecord(at: Date(), heard: open.heard, outcome: "space", title: open.title, ms: ["spaceChanged": ms], step: nil, top: nil))
    }

    public func handle(_ event: HoldEvent) async {
        request += 1
        let mine = request
        switch event {
        case .began:
            holding = true
            let micBegan = Date()
            try? recorder.start()
            micStartMs = Self.elapsed(since: micBegan)
            picker.prepare()
            let (front, snapshot) = (self.front, cards.snapshot)
            frontTask = Task { await front.read(cards: snapshot) }
            if let offer, offer.full {
                offerEpoch += 1               // the list stays on show while fn is held, so the number can still be read
                pill.show(listState(offer, listening: true))
            } else if offer != nil {
                offerEpoch += 1               // the user is answering: stop the countdown and leave the choices on show
                scheduler.after(Self.askAgainAfter) { [weak self] in
                    // Still held: this is no longer "the second one" but a new request, and the pill says so.
                    guard let self, self.holding, self.request == mine, self.offer != nil else { return }
                    self.pill.show(.listening)
                }
            } else {
                scheduler.after(Self.pillDelay) { [weak self] in
                    guard let self, self.holding, self.request == mine else { return }
                    self.pill.show(.listening)
                }
            }
            _ = await frontState()            // normally finishes while the user speaks
        case .cancelled:
            holding = false
            _ = recorder.stop()
            if offer != nil { showOffer() } else { pill.show(.hidden) }
        case .tapped:
            holding = false
            _ = recorder.stop()
            if let offer, offer.full {
                showOffer()                   // a tap picks nothing from the full list
            } else if offer != nil {
                await choose(0, run: Run(request: mine))
            } else {
                show(.hint(PillCopy.keepHolding), for: Self.hintTime, request: mine)
            }
        case .ended(let duration):
            holding = false
            await finish(recorder.stop(), held: duration, request: mine)
        }
    }

    private func finish(_ samples: [Float], held: TimeInterval, request mine: Int) async {
        var run = Run(request: mine)
        run.ms["micStart"] = micStartMs
        run.ms["audio"] = samples.count / 16
        let levels = Transcript.levels(samples)
        run.sound = ["average": Int((levels.average * 10_000).rounded()), "loudest": Int((levels.loudest * 10_000).rounded()),
                     "peak": Int((levels.peak * 10_000).rounded())]
        let choosing = offer != nil
        // While two choices show, a short hold without a word means the second one. A longer hold is a new request.
        let shortHold = held < Self.askAgainAfter
        guard !Transcript.isSilent(samples) else { return choosing && shortHold ? await heldDuringOffer(run) : unheard(run) }
        if !choosing { pill.show(.working(heard: nil)) }

        let transcriber = self.transcriber
        let snapshot = cards.snapshot
        let hint = snapshot.vocabularyHint(extraWords: hintWords())
        let transcribeBegan = Date()
        let raw = await Task.detached(priority: .userInitiated) { transcriber.transcribe(samples, hint: hint) }.value
        run.ms["transcribe"] = Self.elapsed(since: transcribeBegan)
        guard let heard = Transcript.clean(raw) else {
            run.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // A short sound that was not understood, while choices show, was most likely "two".
            return choosing && shortHold && request == mine ? await heldDuringOffer(run) : unheard(run)
        }
        guard request == mine else { return }
        run.heard = heard
        if !choosing { pill.show(.working(heard: heard)) }

        run.front = await frontState()
        guard request == mine else { return }
        // A correction, or a phrase with no word of its own after a request that opened nothing, is understood
        // together with the request before it.
        let joined = FollowUp.joined(new: heard, earlier: earlier?.heard, secondsSince: earlier.map { Date().timeIntervalSince($0.at) } ?? 0,
                                     earlierOpened: earlier?.opened ?? false)
        run.followsEarlier = joined != nil
        earlier = (joined ?? heard, Date(), false)
        let pickBegan = Date()
        let outcome = await picker.pick(transcript: joined ?? heard, cards: snapshot,
                                        context: PickContext(front: run.front.card, choosing: offer != nil))
        run.ms["pick"] = Self.elapsed(since: pickBegan)
        guard request == mine else { return }

        switch outcome {
        case .pickChoice(let index):
            if let offer, offer.targets.indices.contains(index) {
                await choose(index, run: run)
            } else if offer != nil {
                showOffer()                   // no such option: the choices stay
            } else {
                conclude(.nothing(heard: heard, message: PillCopy.nothingMatches), outcome: "nothing", run: run)
            }
        case .open(let target):
            endOffer()
            await open(target, note: PillCopy.backTip, rememberAs: nil, run: run)
        case .choices(let targets, let rememberable):
            endOffer()
            present(targets, rememberable: rememberable && !run.followsEarlier, run: run)
        case .list(let targets):
            endOffer()
            presentList(targets, run: run)
        case .app(let wanted):
            endOffer()
            await closeOrQuit(wanted, run: run)
        case .appInFront(let action):
            endOffer()
            // "Close it": the app in front. A quit is always put as a question, with the app's name, because "it"
            // names nothing; when sessions would end with it, the question says that instead.
            guard let front = appControl?.frontApp() else {
                return conclude(.nothing(heard: heard, message: PillCopy.onlyApps), outcome: "nothing", run: run)
            }
            let target = Target(destination: .app(path: front.path), title: front.name, subtitle: "app", cardKey: "app:\(front.path)")
            let inside = AppRequest.sessionsInside(appNamed: front.name, cards: snapshot)
            let ask: AppRequest.Ask? = action == .quit ? (inside > 0 ? .endsSessions(inside) : .inFront) : nil
            await closeOrQuit(AppRequest(action: action, target: target, ask: ask), run: run)
        case .appUnknown:
            endOffer()
            conclude(.nothing(heard: heard, message: PillCopy.onlyApps), outcome: "nothing", run: run)
        case .back:
            endOffer()
            await goBack(run)
        case .unknownName:
            endOffer()
            conclude(.nothing(heard: heard, message: PillCopy.unknownName), outcome: "nothing", run: run)
        case .cancel:
            endOffer()
            run.step = "control"
            writeLog(outcome: "left", title: nil, run: run)
            pill.show(.hidden)
        case .nothing:
            endOffer()
            conclude(.nothing(heard: heard, message: PillCopy.nothingMatches), outcome: "nothing", run: run)
        }
    }

    /// fn was held while two choices show and nothing was understood: that takes the second choice.
    /// With one choice on show there is no second, so it stays.
    private func heldDuringOffer(_ run: Run) async {
        if let offer, !offer.full, offer.targets.count > 1 {
            await choose(1, run: run)
        } else {
            unheard(run)
        }
    }

    /// Nothing usable was said. While choices show, they stay and the wait starts again.
    private func unheard(_ run: Run) {
        if offer != nil {
            writeLog(outcome: "unheard", title: nil, run: run)
            showOffer()
        } else {
            conclude(.nothing(heard: "", message: PillCopy.didNotCatch), outcome: "unheard", run: run)
        }
    }

    /// What was in front when the key went down, or "nothing known" when the read has not finished in time.
    private func frontState() async -> FrontState {
        let unknown = FrontState(card: .none, destination: nil)
        guard let task = frontTask else { return unknown }
        let seconds = Self.frontWait
        let first = FirstToFinish()
        return await withCheckedContinuation { (continuation: CheckedContinuation<FrontState, Never>) in
            Task {
                let state = await task.value
                if first.claim() { continuation.resume(returning: state) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if first.claim() { continuation.resume(returning: unknown) }
            }
        }
    }

    // MARK: Two choices

    private func present(_ targets: [Target], rememberable: Bool, run: Run) {
        guard !targets.isEmpty else {
            return conclude(.nothing(heard: run.heard, message: PillCopy.nothingMatches), outcome: "nothing", run: run)
        }
        offer = Offer(heard: run.heard, targets: targets, rememberable: rememberable)
        writeLog(outcome: "offered", title: targets.map(\.title).joined(separator: " | "), run: run)
        showOffer()
    }

    /// The list of every open session, on request ("show all sessions").
    private func presentList(_ targets: [Target], run: Run) {
        guard !targets.isEmpty else {
            return conclude(.nothing(heard: run.heard, message: PillCopy.noSessions), outcome: "nothing", run: run)
        }
        offer = Offer(heard: run.heard, targets: targets, rememberable: false, full: true)
        var run = run
        run.step = "control"
        writeLog(outcome: "listed", title: "\(targets.count) sessions", run: run)
        showOffer()
    }

    /// The rows of the full list: each session with when it was last used, as far as that is known.
    private func listState(_ offer: Offer, listening: Bool) -> PillState {
        let snapshot = cards.snapshot
        let now = Date()
        let options = offer.targets.map { target -> PillOption in
            let active = snapshot.sessions.first { "session:\($0.id)" == target.cardKey }?.lastActive
            let subtitle = active.map { "\(target.subtitle) · \(Ago.short(now.timeIntervalSince($0)))" } ?? target.subtitle
            return PillOption(title: target.title, subtitle: subtitle)
        }
        return .list(options: options, more: max(0, snapshot.sessions.count - offer.targets.count), listening: listening)
    }

    /// A key was pressed while a numbered list had the keyboard: a number picks that row, anything else closes the list.
    public func typed(_ key: PillKey) async {
        guard let offer else { return }
        request += 1
        let mine = request
        switch key {
        case .number(let number):
            if offer.targets.indices.contains(number - 1) {
                await choose(number - 1, run: Run(request: mine))
            } else {
                showOffer()                   // no such row: the list stays
            }
        case .other:
            endOffer()
            var run = Run(heard: offer.heard, request: mine)
            run.step = "key"
            writeLog(outcome: "left", title: nil, run: run)
            pill.show(.hidden)
        }
    }

    /// Puts the choices (back) on show and starts the wait for an answer again.
    private func showOffer() {
        guard let offer else { return }
        if offer.full {
            pill.show(listState(offer, listening: false))
        } else if let question = offer.question, let target = offer.targets.first {
            pill.show(.choices(heard: offer.heard, options: [PillOption(title: PillCopy.quitQuestion(target.title), subtitle: question.why)]))
        } else {
            pill.show(.choices(heard: offer.heard, options: offer.targets.map { PillOption(title: $0.title, subtitle: $0.subtitle) }))
        }
        startOfferCountdown()
    }

    private func startOfferCountdown() {
        offerEpoch += 1
        let epoch = offerEpoch
        let seconds = offer?.full == true ? thresholds.listTimeoutS : thresholds.choiceTimeoutS
        scheduler.after(TimeInterval(seconds)) { [weak self] in
            guard let self, let offer = self.offer, self.offerEpoch == epoch else { return }
            self.endOffer()
            self.request += 1
            self.conclude(.nothing(heard: offer.heard, message: PillCopy.leftAlone), outcome: "left",
                          run: Run(heard: offer.heard, request: self.request))
        }
    }

    private func endOffer() {
        offer = nil
        offerEpoch += 1
    }

    private func choose(_ index: Int, run: Run) async {
        guard let chosen = offer, chosen.targets.indices.contains(index) else { return }
        endOffer()
        var run = run
        run.heard = chosen.heard
        run.step = "choice"
        if let question = chosen.question {
            return await perform(question.action, on: chosen.targets[index], run: run)
        }
        run.front = await frontState()
        await open(chosen.targets[index], note: chosen.rememberable ? PillCopy.remembered : PillCopy.backTip,
                   rememberAs: chosen.rememberable ? chosen.heard : nil, run: run)
    }

    // MARK: Closing and quitting apps

    /// "Close Spotify" or "quit Spotify". An app that is not open is left alone; a quit that could cost something
    /// (sessions would end, or the name was unclear) is put as a question first.
    private func closeOrQuit(_ wanted: AppRequest, run: Run) async {
        guard let appControl, case .app(let path) = wanted.target.destination else {
            return conclude(.nothing(heard: run.heard, message: PillCopy.couldNotClose), outcome: "failed", title: wanted.target.title, run: run)
        }
        guard appControl.isRunning(path: path) else {
            return conclude(.nothing(heard: run.heard, message: PillCopy.notRunning(wanted.target.title)), outcome: "nothing",
                            title: wanted.target.title, run: run)
        }
        // Finder holds the desktop; without it the Mac looks broken. It can be hidden, never quit.
        if wanted.action == .quit, path.hasSuffix("/CoreServices/Finder.app") {
            return conclude(.nothing(heard: run.heard, message: PillCopy.finderStays), outcome: "nothing", title: wanted.target.title, run: run)
        }
        guard let ask = wanted.ask else { return await perform(wanted.action, on: wanted.target, run: run) }
        let why: String
        switch ask {
        case .unsureOfName: why = PillCopy.unsureOfName
        case .inFront: why = PillCopy.appInFront
        case .endsSessions(let count): why = PillCopy.endsSessions(count)
        }
        offer = Offer(heard: run.heard, targets: [wanted.target], rememberable: false, question: (wanted.action, why))
        writeLog(outcome: "offered", title: PillCopy.quitQuestion(wanted.target.title), run: run)
        showOffer()
    }

    private func perform(_ action: AppAction, on target: Target, run: Run) async {
        guard let appControl, case .app(let path) = target.destination else {
            return conclude(.nothing(heard: run.heard, message: PillCopy.couldNotClose), outcome: "failed", title: target.title, run: run)
        }
        let result = action == .hide ? await appControl.hide(path: path) : await appControl.quit(path: path)
        let name = target.title
        switch (result, action) {
        case (.done, .hide):
            earlier?.opened = true
            conclude(.opened(heard: run.heard, title: name, subtitle: PillCopy.hidden, note: PillCopy.hiddenNote(name)),
                     outcome: "hidden", title: name, run: run)
        case (.done, .quit):
            earlier?.opened = true
            conclude(.opened(heard: run.heard, title: name, subtitle: PillCopy.quitDone, note: PillCopy.quitNote(name)),
                     outcome: "quit", title: name, run: run)
        case (.asked, _):
            earlier?.opened = true
            conclude(.opened(heard: run.heard, title: name, subtitle: PillCopy.quitAsked, note: PillCopy.quitAskedNote),
                     outcome: "quit", title: name, run: run)
        case (.notRunning, _):
            conclude(.nothing(heard: run.heard, message: PillCopy.notRunning(name)), outcome: "nothing", title: name, run: run)
        case (.failed, _):
            conclude(.nothing(heard: run.heard, message: PillCopy.couldNotClose), outcome: "failed", title: name, run: run)
        }
    }

    // MARK: Opening

    private func open(_ target: Target, note: String, rememberAs phrase: String?, run: Run) async {
        var run = run
        let openBegan = Date()
        do {
            let openerNote = try await opener.open(target.destination)
            run.ms["open"] = Self.elapsed(since: openBegan)
            backDestination = run.front.destination
            lastOpen = (run.released, run.heard, target.title)
            earlier?.opened = true
            if let phrase { remembered?.remember(phrase, cardKey: target.cardKey) }
            conclude(.opened(heard: run.heard, title: target.title, subtitle: target.subtitle, note: openerNote ?? note),
                     outcome: "opened", title: target.title, run: run)
        } catch OpenError.gone {
            // A folder that is not there is most likely on a drive that is unplugged: it will be back, so it stays remembered.
            if case .folder = target.destination {
                return conclude(.nothing(heard: run.heard, message: PillCopy.folderGone), outcome: "gone", title: target.title, run: run)
            }
            // A remembered phrase that leads to something closed is of no use any more.
            if remembered?.cardKey(for: run.heard) == target.cardKey { remembered?.forget(run.heard) }
            conclude(.nothing(heard: run.heard, message: PillCopy.noLongerOpen), outcome: "gone", title: target.title, run: run)
        } catch OpenError.notPermitted(let app) {
            conclude(.nothing(heard: run.heard, message: PillCopy.notPermitted(app)), outcome: "failed", title: target.title, run: run)
        } catch {
            conclude(.nothing(heard: run.heard, message: PillCopy.couldNotOpen), outcome: "failed", title: target.title, run: run)
        }
    }

    /// "Back": return to where the user was before the last open. Saying it again returns once more.
    private func goBack(_ run: Run) async {
        var run = run
        guard let destination = backDestination else {
            return conclude(.nothing(heard: run.heard, message: PillCopy.nothingToGoBackTo), outcome: "nothing", run: run)
        }
        let (title, subtitle) = describe(destination)
        let openBegan = Date()
        do {
            _ = try await opener.open(destination)
            run.ms["open"] = Self.elapsed(since: openBegan)
            backDestination = run.front.destination
            conclude(.opened(heard: run.heard, title: title, subtitle: subtitle, note: PillCopy.backTip), outcome: "back", title: title, run: run)
        } catch OpenError.gone {
            backDestination = nil
            conclude(.nothing(heard: run.heard, message: PillCopy.noLongerOpen), outcome: "gone", title: title, run: run)
        } catch {
            conclude(.nothing(heard: run.heard, message: PillCopy.couldNotOpen), outcome: "failed", title: title, run: run)
        }
    }

    /// Words for a place that may not be a card: the card's own words when it is one.
    private func describe(_ destination: Destination) -> (title: String, subtitle: String) {
        let snapshot = cards.snapshot
        switch destination {
        case .terminalTab(let tty):
            if let session = snapshot.sessions.first(where: { $0.host == .terminal && $0.tty == tty }) {
                let target = snapshot.target(for: session)
                return (target.title, target.subtitle)
            }
            return ("Terminal", "tab")
        case .vscodeTerminal(let shellPid, let folderPath):
            if let session = snapshot.sessions.first(where: { $0.host == .vscode && $0.shellPid == shellPid }) {
                let target = snapshot.target(for: session)
                return (target.title, target.subtitle)
            }
            return ("VS Code", URL(fileURLWithPath: folderPath).lastPathComponent)
        case .artifact(let url):
            if let artifact = snapshot.artifacts.first(where: { $0.url == url }) {
                let target = snapshot.target(for: artifact)
                return (target.title, target.subtitle)
            }
            return (url.host ?? "Chrome", "Chrome")
        case .site(let url):
            return (url.host ?? "Chrome", "Chrome")
        case .app(let path):
            return (URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, "app")
        case .folder(let path):
            return (URL(fileURLWithPath: path).lastPathComponent, "Finder")
        }
    }

    // MARK: Results

    /// Writes the log line for a finished request and shows its result for a few seconds.
    private func conclude(_ state: PillState, outcome: String, title: String? = nil, run: Run) {
        writeLog(outcome: outcome, title: title, run: run)
        guard request == run.request else { return }
        show(state, for: Self.resultTime, request: run.request)
    }

    private func writeLog(outcome: String, title: String?, run: Run) {
        var ms = run.ms
        ms["total"] = Self.elapsed(since: run.released)
        let trace = run.heard.isEmpty || run.step != nil ? nil : lastTrace()
        log.write(EventRecord(at: Date(), heard: run.heard, outcome: outcome, title: title, ms: ms, step: run.step ?? trace?.step, top: trace?.top, sound: run.sound, raw: run.raw,
                              jev: trace.flatMap { $0.answers.isEmpty ? nil : $0.answers }))
    }

    private func show(_ state: PillState, for seconds: TimeInterval, request mine: Int) {
        pill.show(state)
        scheduler.after(seconds) { [weak self] in
            guard let self, self.request == mine else { return }
            self.pill.show(.hidden)
        }
    }

    private static func elapsed(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }
}

/// Lets exactly one of two racing tasks answer.
private final class FirstToFinish: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.withLock {
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
