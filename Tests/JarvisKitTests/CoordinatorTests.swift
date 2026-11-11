import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

@MainActor @Suite struct CoordinatorTests {
    @Test func aNamedSiteOpens() async {
        let k = Kit(heard: "Open YouTube.")
        await k.hold()
        #expect(k.opener.opened == [.site(url: URL(string: "https://www.youtube.com/")!)])
        #expect(k.pill.last == .opened(heard: "Open YouTube.", title: "YouTube", subtitle: "Chrome", note: PillCopy.backTip))
    }

    @Test func silenceOpensNothing() async {
        let k = Kit(heard: "[BLANK_AUDIO]")
        await k.hold()
        #expect(k.opener.opened.isEmpty)
        #expect(k.picker.calls == 0)
        #expect(k.pill.last == .nothing(heard: "", message: PillCopy.didNotCatch))
    }

    @Test func aQuietRecordingIsNotEvenTranscribed() async {
        let k = Kit(heard: "open YouTube")
        k.recorder.samples = [Float](repeating: 0, count: 16_000)
        await k.hold()
        #expect(k.transcriber.calls == 0)
        #expect(k.picker.calls == 0)
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == .nothing(heard: "", message: PillCopy.didNotCatch))
    }

    @Test func aClosedDestinationIsReported() async {
        let k = Kit(heard: "open YouTube")
        k.opener.error = .gone
        await k.hold()
        #expect(k.pill.last == .nothing(heard: "open YouTube", message: PillCopy.noLongerOpen))
    }

    @Test func aFailedOpenSaysSoAndDoesNotCrash() async {
        let k = Kit(heard: "open YouTube")
        k.opener.error = .notPermitted("Google Chrome")
        await k.hold()
        #expect(k.pill.last == .nothing(heard: "open YouTube", message: PillCopy.notPermitted("Google Chrome")))
        k.opener.error = .failed("boom")
        await k.hold()
        #expect(k.pill.last == .nothing(heard: "open YouTube", message: PillCopy.couldNotOpen))
    }

    @Test func noMatchSaysSo() async {
        let k = Kit(heard: "open the session about my tax return")
        await k.hold()
        #expect(k.pill.last == .nothing(heard: "open the session about my tax return", message: PillCopy.nothingMatches))
    }

    @Test func aTapWhileIdleShowsTheHint() async {
        let k = Kit(heard: "")
        await k.coordinator.handle(.tapped)
        #expect(k.pill.last == .hint(PillCopy.keepHolding))
        k.scheduler.advance(by: 1.5)
        #expect(k.pill.last == .hidden)
    }

    @Test func aCancelDiscardsTheRecording() async {
        let k = Kit(heard: "open YouTube")
        await k.coordinator.handle(.began)
        await k.coordinator.handle(.cancelled)
        #expect(k.transcriber.calls == 0)
        #expect(k.pill.last == .hidden)
        k.scheduler.advance(by: 1)
        #expect(k.pill.last == .hidden)          // the delayed "Listening" must not appear after a cancel
    }

    @Test func listeningAppearsOnlyAfterAShortDelay() async {
        let k = Kit(heard: "open YouTube")
        await k.coordinator.handle(.began)
        #expect(k.recorder.starts == 1)
        #expect(k.pill.states.isEmpty)
        k.scheduler.advance(by: 0.15)
        #expect(k.pill.last == .listening)
    }

    @Test func theResultGoesAwayAfterThreeSeconds() async {
        let k = Kit(heard: "open YouTube")
        await k.hold()
        k.scheduler.advance(by: 2.9)
        #expect(k.pill.last != .hidden)
        k.scheduler.advance(by: 0.2)
        #expect(k.pill.last == .hidden)
    }

    @Test func everyRequestIsLoggedWithItsTimes() async {
        let k = Kit(heard: "open YouTube")
        await k.hold()
        let record = k.logged.last
        #expect(record?.heard == "open YouTube")
        #expect(record?.outcome == "opened")
        #expect(record?.title == "YouTube")
        let timed = Set((record?.ms ?? [:]).keys)
        #expect(timed.isSuperset(of: ["transcribe", "pick", "open", "total"]))
        let quiet = Kit(heard: "(silence)")
        await quiet.hold()
        #expect(quiet.logged.last?.outcome == "unheard")
    }

    @Test func theHintReachesTheTranscriber() async throws {
        let k = Kit(heard: "open YouTube", cards: try Fixture.cards(), hintWords: ["Notes"])
        await k.hold()
        #expect(k.transcriber.lastHint.contains("insta comment dm"))
        #expect(k.transcriber.lastHint.hasSuffix("Notes"))
    }

    @Test func thePickerIsPreparedWhenTheKeyGoesDown() async {
        let k = Kit(heard: "open YouTube")
        await k.coordinator.handle(.began)
        #expect(k.picker.prepareCalls == 1)
    }

    @Test func whatIsInFrontWhenTheKeyGoesDownReachesThePicker() async {
        let k = Kit(heard: "open the artifact")
        k.front.state = FrontState(card: .session(id: "s-discovery"), destination: .terminalTab(tty: "/dev/ttys001"))
        await k.coordinator.handle(.began)
        k.front.state = FrontState(card: .none, destination: nil)        // what is in front later does not matter
        await k.coordinator.handle(.ended(duration: 1))
        #expect(k.picker.contexts.last == PickContext(front: .session(id: "s-discovery"), choosing: false))
    }

    @Test func theLogSaysHowThePickWasMade() async {
        let k = Kit(heard: "open YouTube")
        k.trace = PickTrace(step: "name", kind: nil, known: nil, top: ["YouTube": 1])
        await k.hold()
        #expect(k.logged.last?.step == "name")
        #expect(k.logged.last?.top == ["YouTube": 1])
    }

    @Test func aDesktopSwitchRightAfterAnOpenIsTimed() async {
        let k = Kit(heard: "open YouTube")
        k.coordinator.spaceChanged()
        #expect(k.logged.isEmpty)                       // no open came before it
        await k.hold()
        k.coordinator.spaceChanged()
        #expect(k.logged.last?.outcome == "space")
        #expect(k.logged.last?.ms["spaceChanged"] != nil)
        k.coordinator.spaceChanged()
        #expect(k.logged.filter { $0.outcome == "space" }.count == 1)    // only the first change after an open counts
    }

    // From the first hand test: clips were judged silent and there was no number to say how quiet they were.
    @Test func theLogSaysHowLoudTheRecordingWas() async {
        let k = Kit(heard: "open YouTube")
        await k.hold()
        let sound = k.logged.last?.sound ?? [:]
        #expect((sound["loudest"] ?? 0) > 500)             // the test tone has a level of about 0.07; values are in 1/10000
        #expect(sound["average"] != nil && sound["peak"] != nil)
        let quiet = Kit(heard: "x")
        quiet.recorder.samples = [Float](repeating: 0.0001, count: 16_000)
        await quiet.hold()
        #expect(quiet.logged.last?.outcome == "unheard")
        #expect(quiet.logged.last?.sound?["peak"] == 1)
    }

    @Test func theScriptThatListsClaudeTabsIsValid() throws {
        #expect(ChromeScripts.claudeTabs.contains("with timeout of 3 seconds"))
        // Inside a Chrome script the bare word `tab` is Chrome's own class, not the tab character: titles came back empty.
        #expect(!ChromeScripts.claudeTabs.contains("& tab &"))
        #expect(ChromeScripts.claudeTabs.contains("character id 9"))
        #expect(try compiles(ChromeScripts.claudeTabs))
        #expect(ChromeScripts.parseTabs("https://claude.ai/artifact/a\tFirst page | Claude\nhttps://claude.ai/artifact/b\t\n\n").map(\.title) == ["First page | Claude", ""])
    }
}
