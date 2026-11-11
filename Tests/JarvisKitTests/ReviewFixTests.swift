import AppKit
import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

/// A picker that waits until the test lets it answer.
final class GatedPicker: Picking, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var started = 0
    let outcome: Outcome
    init(outcome: Outcome) { self.outcome = outcome }
    var startedCount: Int { lock.withLock { started } }
    func release() {
        let held = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { waiting = [] }
            return waiting
        }
        held.forEach { $0.resume() }
    }
    func pick(transcript: String, cards: CardSnapshot, context: PickContext) async -> Outcome {
        await withCheckedContinuation { continuation in
            lock.withLock {
                started += 1
                waiting.append(continuation)
            }
        }
        return outcome
    }
}

/// A front reader that never answers: an app that does not reply to Apple events, or a consent question left open.
struct HungFront: FrontReading {
    func read(cards: CardSnapshot) async -> FrontState {
        try? await Task.sleep(nanoseconds: 60_000_000_000)
        return FrontState(card: .none, destination: nil)
    }
}

@MainActor func settle(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }

/// Tests added for the findings of the whole-branch review. Key events are sent as the app sends them: one task each.
@MainActor @Suite(.serialized) struct ReviewFixTests {
    let site = Kit.defaultCards.target(for: Kit.defaultCards.sites[0])

    func wired(picker: Picking, front: FrontReading) -> (Coordinator, FakeOpener, FakePill) {
        let opener = FakeOpener(), pill = FakePill()
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-review-\(UUID().uuidString).jsonl")
        let coordinator = Coordinator(recorder: FakeRecorder(), transcriber: FakeTranscriber("open the insta session"), picker: picker,
                                      opener: opener, front: front, cards: FakeCards(Kit.defaultCards), pill: pill,
                                      log: EventLog(file: log), thresholds: Thresholds(), scheduler: FakeScheduler())
        return (coordinator, opener, pill)
    }

    // Finding 1: the panel must be sized for the state it is about to show, not for the one before.
    @Test func thePillIsSizedForTheStateItShows() {
        _ = NSApplication.shared
        let controller = PillController()
        let opened = PillState.opened(heard: "Open the open source insta to comment session.", title: "Shareable repo setup guide",
                                      subtitle: "VS Code · insta-comment-dm", note: PillCopy.backTip)
        let choices = PillState.choices(heard: "Open the insta session.", options: [
            PillOption(title: "IDEAS2 Instagram reel tracking", subtitle: "VS Code · insta-comment-dm"),
            PillOption(title: "Shareable repo setup guide", subtitle: "VS Code · insta-comment-dm")])
        for state in [PillState.listening, opened, choices, .hint(PillCopy.keepHolding), choices, .listening] {
            #expect(controller.place(state) == PillController.size(for: state), "\(state)")
        }
    }

    @Test func aPillIsOnlyAsWideAsItsWords() {
        _ = NSApplication.shared
        let listening = PillController.size(for: .listening)
        let choices = PillController.size(for: .choices(heard: "Open the insta session.", options: [
            PillOption(title: "IDEAS2 Instagram reel tracking", subtitle: "VS Code · insta-comment-dm"),
            PillOption(title: "Shareable repo setup guide", subtitle: "VS Code · insta-comment-dm")]))
        let long = PillController.size(for: .nothing(heard: String(repeating: "a very long sentence that was heard ", count: 6), message: PillCopy.nothingMatches))
        #expect(listening.width < 200)
        #expect(listening.height < 60)
        #expect(choices.height > 120)
        #expect(choices.width <= PillView.maxWidth)
        #expect(long.width <= PillView.maxWidth)                               // long text wraps instead of widening the pill
    }

    // Finding 4: how long fn was held is taken from the events' own times, not from when Jarvis got round to them.
    @Test func holdLengthComesFromTheEventsOwnTimes() throws {
        var seen: [HoldEvent] = []
        let monitor = KeyMonitor { seen.append($0) }
        func flagsChanged(_ flags: CGEventFlags, atSeconds seconds: Double) throws -> CGEvent {
            let event = try #require(CGEvent(source: nil))
            event.type = .flagsChanged
            event.flags = flags
            event.timestamp = CGEventTimestamp(seconds * 1_000_000_000)
            return event
        }
        // Both events are handled within a moment of each other, as happens when the main thread was busy.
        monitor.handle(type: .flagsChanged, event: try flagsChanged(.maskSecondaryFn, atSeconds: 500.0))
        monitor.handle(type: .flagsChanged, event: try flagsChanged([], atSeconds: 501.25))
        monitor.handle(type: .flagsChanged, event: try flagsChanged(.maskSecondaryFn, atSeconds: 510.0))
        monitor.handle(type: .flagsChanged, event: try flagsChanged([], atSeconds: 510.15))
        #expect(seen == [.began, .ended(duration: 1.25), .began, .tapped])
    }

    // Finding 5: a read of what is in front that never returns must not hold the request.
    @Test func aFrontReadThatHangsDoesNotHangTheRequest() async {
        let (coordinator, opener, pill) = wired(picker: FakePicker(outcome: .open(site)), front: HungFront())
        Task { @MainActor in await coordinator.handle(.began) }
        await settle(50)
        Task { @MainActor in await coordinator.handle(.ended(duration: 1)) }
        await settle(1500)
        #expect(opener.opened == [site.destination], "nothing opened; the pill shows \(String(describing: pill.last))")
    }

    @Test func scriptsGiveUpOnAnAppThatDoesNotAnswer() throws {
        let scripts = [try TerminalScripts.focusTab(tty: "/dev/ttys012"), TerminalScripts.frontTTY, ChromeScripts.frontURL,
                       try ChromeScripts.focusOrOpen(.site(url: URL(string: "https://www.youtube.com/")!))]
        for script in scripts {
            #expect(script.contains("with timeout of 3 seconds"))
            #expect(try compiles(script))
        }
    }

    // Finding 9: a new hold while the earlier request still waits for its answer. The earlier answer must not open anything.
    @Test func aStaleResultNeverOpens() async {
        let gate = GatedPicker(outcome: .open(site))
        let (coordinator, opener, _) = wired(picker: gate, front: NothingInFront())
        Task { @MainActor in await coordinator.handle(.began) }
        await settle(30)
        Task { @MainActor in await coordinator.handle(.ended(duration: 1)) }
        await settle(100)
        #expect(gate.startedCount == 1)                                          // request 1 is waiting for the picker
        Task { @MainActor in await coordinator.handle(.began) }                 // the user holds fn again
        await settle(30)
        gate.release()                                                           // request 1's answer arrives now
        await settle(100)
        #expect(opener.opened.isEmpty)
    }

    // Finding 6: a window that owns the terminal but answers late is not a closed terminal.
    @Test func aSlowWindowIsNotReportedAsAClosedTerminal() async throws {
        let dir = try shortDir()
        let other = try FakeAddon(dir: dir, pid: 77, owns: [1], active: 1)
        let owner = try FakeAddon(dir: dir, pid: 78, owns: [4300], active: 4300, folders: ["/work/deck"], delayMs: 300)
        let log = RaiseLog()
        let opener = VSCodeOpener(bridge: VSCodeBridge(socketDir: dir)) { log.add($0) }
        #expect(try await opener.open(.vscodeTerminal(shellPid: 4300, folderPath: "/elsewhere")) == nil)
        #expect(owner.focused.contains(4300))
        #expect(log.paths == ["/work/deck"])
        _ = other
    }

    @Test func aWindowThatNeverAnswersIsNotReportedAsAClosedTerminal() async throws {
        let dir = try shortDir()
        let other = try FakeAddon(dir: dir, pid: 77, owns: [1], active: 1)
        let silent = try FakeAddon(dir: dir, pid: 78, owns: [4300], active: 4300, silent: true)
        let log = RaiseLog()
        let opener = VSCodeOpener(bridge: VSCodeBridge(socketDir: dir)) { log.add($0) }
        #expect(try await opener.open(.vscodeTerminal(shellPid: 4300, folderPath: "/work/deck")) == VSCodeOpener.slowNote)
        #expect(log.paths == ["/work/deck"])                                     // the window still comes forward
        _ = (other, silent)
    }
}
