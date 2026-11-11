import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

@MainActor @Suite struct CoordinatorChoiceTests {
    let cards: CardSnapshot
    let ideas: Target
    let share: Target
    let phrase = "open the insta session"
    let youTube = URL(string: "https://www.youtube.com/")!
    let notes = Destination.app(path: "/System/Applications/Notes.app")

    init() throws {
        cards = try Fixture.cards()
        ideas = cards.target(for: cards.sessions.first { $0.id == "s-ideas" }!)
        share = cards.target(for: cards.sessions.first { $0.id == "s-share" }!)
    }

    func opt(_ target: Target) -> PillOption { PillOption(title: target.title, subtitle: target.subtitle) }

    /// A kit that has just offered the two insta sessions.
    func offering(rememberable: Bool = true, targets: [Target]? = nil) async -> Kit {
        let k = Kit(heard: phrase, cards: cards, outcome: .choices(targets ?? [ideas, share], rememberable: rememberable))
        await k.hold()
        return k
    }

    @Test func aTapTakesTheFirstChoiceAndRemembersIt() async {
        let k = await offering()
        #expect(k.pill.last == .choices(heard: phrase, options: [opt(ideas), opt(share)]))
        #expect(k.opener.opened.isEmpty)
        await k.coordinator.handle(.tapped)
        #expect(k.opener.opened == [ideas.destination])
        #expect(k.remembered.cardKey(for: phrase) == ideas.cardKey)
        #expect(k.pill.last == .opened(heard: phrase, title: ideas.title, subtitle: ideas.subtitle, note: PillCopy.remembered))
    }

    @Test func sayingTwoTakesTheSecond() async {
        let k = await offering()
        k.transcriber.next = "Two."
        await k.hold()
        #expect(k.picker.contexts.last?.choosing == true)
        #expect(k.opener.opened == [share.destination])
        #expect(k.remembered.cardKey(for: phrase) == share.cardKey)
        #expect(k.pill.last == .opened(heard: phrase, title: share.title, subtitle: share.subtitle, note: PillCopy.remembered))
    }

    @Test func leavingItAloneMovesNothing() async {
        let k = await offering()
        k.scheduler.advance(by: 7.9)
        #expect(k.pill.last == .choices(heard: phrase, options: [opt(ideas), opt(share)]))
        k.scheduler.advance(by: 0.2)
        #expect(k.pill.last == .nothing(heard: phrase, message: PillCopy.leftAlone))
        #expect(k.opener.opened.isEmpty)
        #expect(k.remembered.cardKey(for: phrase) == nil)
        await k.coordinator.handle(.tapped)                         // the choices are gone: a tap is only a tap again
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == .hint(PillCopy.keepHolding))
    }

    @Test func unrememberableChoicesAreNotStored() async {
        let k = await offering(rememberable: false)
        await k.coordinator.handle(.tapped)
        #expect(k.opener.opened == [ideas.destination])
        #expect(k.remembered.cardKey(for: phrase) == nil)
        #expect(k.pill.last == .opened(heard: phrase, title: ideas.title, subtitle: ideas.subtitle, note: PillCopy.backTip))
    }

    @Test func aNewRequestWhileChoosingReplacesTheChoices() async {
        let k = await offering()
        k.picker.outcome = nil
        k.transcriber.next = "open YouTube"
        await k.hold()
        #expect(k.opener.opened == [.site(url: youTube)])
        #expect(k.remembered.cardKey(for: phrase) == nil)
        #expect(k.remembered.cardKey(for: "open YouTube") == nil)
        k.scheduler.advance(by: 2)
        #expect(k.pill.last == .opened(heard: "open YouTube", title: "YouTube", subtitle: "Chrome", note: PillCopy.backTip))   // no late "left alone"
    }

    @Test func aNumberWithNoSuchOptionKeepsTheChoices() async {
        let k = await offering(targets: [ideas])
        k.transcriber.next = "two"
        await k.hold()
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == .choices(heard: phrase, options: [opt(ideas)]))
        await k.coordinator.handle(.tapped)
        #expect(k.opener.opened == [ideas.destination])
    }

    @Test func theChoicesStayUpWhileTheUserAnswers() async {
        let k = await offering()
        k.scheduler.advance(by: 6)
        await k.coordinator.handle(.began)                          // the user starts to answer near the end of the wait
        k.scheduler.advance(by: 0.5)
        #expect(k.pill.last == .choices(heard: phrase, options: [opt(ideas), opt(share)]))     // not "Listening" yet
        k.scheduler.advance(by: 3)
        #expect(k.pill.last == .listening)                          // and never "Left alone" while fn is down
    }

    // From the second hand test: "two" was written as "2" and thrown away, and the user asked for a way to take the
    // second choice that does not depend on speech. Tap is 1; a hold is 2.
    @Test func theDigitTwoTakesTheSecond() async {
        let k = await offering()
        k.transcriber.next = " 2"
        await k.hold()
        #expect(k.opener.opened == [share.destination])
    }

    @Test func holdingWithoutSpeakingTakesTheSecond() async {
        let k = await offering()
        k.recorder.samples = [Float](repeating: 0, count: 8_000)    // fn held for half a second, nothing said
        await k.hold(for: 0.5)
        #expect(k.opener.opened == [share.destination])
        #expect(k.transcriber.calls == 1)                           // only the first request was transcribed
        #expect(k.remembered.cardKey(for: phrase) == share.cardKey)
        #expect(k.logged.last?.step == "choice")
    }

    @Test func aShortHoldThatWasNotUnderstoodTakesTheSecond() async {
        let k = await offering()
        k.transcriber.next = "(mumbles)"
        await k.hold(for: 0.7)                                      // a short sound, no usable words
        #expect(k.opener.opened == [share.destination])
    }

    @Test func aLongHoldThatWasNotUnderstoodKeepsTheChoices() async {
        let k = await offering()
        k.transcriber.next = "(mumbles)"
        k.recorder.samples = (0..<4 * 16_000).map { 0.1 * sin(Float($0) * 2 * .pi * 440 / 16_000) }     // four seconds: a sentence, not "two"
        await k.hold(for: 4)
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == .choices(heard: phrase, options: [opt(ideas), opt(share)]))
        #expect(k.logged.last?.outcome == "unheard")
        #expect(k.logged.last?.raw == "(mumbles)")                  // what the speech model wrote is kept for diagnosis
    }

    // From the third hand test: when both choices are wrong, the user wants to keep fn down and ask for something
    // else, and to SEE the moment the hold stops meaning "the second one".
    @Test func keepingFnDownTurnsTheAnswerIntoANewRequest() async {
        let k = await offering()
        await k.coordinator.handle(.began)
        k.scheduler.advance(by: 0.8)
        #expect(k.pill.last == .choices(heard: phrase, options: [opt(ideas), opt(share)]))     // still a short hold: it would mean 2
        k.scheduler.advance(by: 0.2)
        #expect(k.pill.last == .listening)                                                     // from here on it is a new request
        k.recorder.samples = [Float](repeating: 0, count: 32_000)
        await k.coordinator.handle(.ended(duration: 2))                                        // but nothing was said
        #expect(k.opener.opened.isEmpty)                                                       // a long silent hold is not "2"
        #expect(k.pill.last == .choices(heard: phrase, options: [opt(ideas), opt(share)]))     // the choices are back
        k.picker.outcome = nil
        k.recorder.samples = FakeRecorder.tone
        k.transcriber.next = "open YouTube"
        await k.hold(for: 2)
        #expect(k.opener.opened == [.site(url: youTube)])
    }

    // From the third hand test: "no, the artifact in Chrome" right after a request that went wrong.
    @Test func aCorrectionCarriesTheRequestBeforeIt() async {
        let k = Kit(heard: "open the pattern selection artifact", cards: cards, outcome: .nothing)
        await k.hold()
        k.transcriber.next = "no, the artifact in chrome"
        await k.hold()
        #expect(k.picker.transcripts == ["open the pattern selection artifact", "open the pattern selection artifact. no, the artifact in chrome"])
        #expect(k.logged.last?.heard == "no, the artifact in chrome")                          // the log keeps what was said this time
        k.transcriber.next = "open YouTube"
        await k.hold()
        #expect(k.picker.transcripts.last == "open YouTube")                                   // a plain new request stands alone
    }

    @Test func choicesFromACorrectionAreNotRemembered() async {
        let k = Kit(heard: "open the pattern selection artifact", cards: cards, outcome: .nothing)
        await k.hold()
        k.picker.outcome = .choices([ideas, share], rememberable: true)
        k.transcriber.next = "no, the session"
        await k.hold()
        await k.coordinator.handle(.tapped)
        #expect(k.opener.opened == [ideas.destination])
        #expect(k.remembered.cardKey(for: "no, the session") == nil)
    }

    @Test func aHoldWithOnlyOneChoiceOnShowKeepsIt() async {
        let k = await offering(targets: [ideas])
        k.recorder.samples = [Float](repeating: 0, count: 8_000)
        await k.hold(for: 0.5)
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == .choices(heard: phrase, options: [opt(ideas)]))
    }

    @Test func anotherKeyDuringTheAnswerKeepsTheChoices() async {
        let k = await offering()
        await k.coordinator.handle(.began)
        await k.coordinator.handle(.cancelled)
        #expect(k.pill.last == .choices(heard: phrase, options: [opt(ideas), opt(share)]))
        k.scheduler.advance(by: 8)
        #expect(k.pill.last == .nothing(heard: phrase, message: PillCopy.leftAlone))
    }

    @Test func backReturnsToWhereTheUserWas() async {
        let k = Kit(heard: "open YouTube")
        k.front.state = FrontState(card: .none, destination: notes)
        await k.hold()
        k.front.state = FrontState(card: .none, destination: .artifact(url: youTube))     // the user is now on YouTube
        k.transcriber.next = "back"
        await k.hold()
        #expect(k.opener.opened.last == notes)
        #expect(k.pill.last == .opened(heard: "back", title: "Notes", subtitle: "app", note: PillCopy.backTip))
        #expect(k.logged.last?.outcome == "back")

        k.front.state = FrontState(card: .none, destination: notes)                       // saying it again returns to YouTube
        await k.hold()
        #expect(k.opener.opened.last == .artifact(url: youTube))
    }

    @Test func backNamesASessionByItsTitle() async {
        let k = Kit(heard: "open YouTube", cards: cards)
        k.front.state = FrontState(card: .session(id: "s-share"), destination: share.destination)
        await k.hold()
        k.transcriber.next = "Back."
        await k.hold()
        #expect(k.pill.last == .opened(heard: "Back.", title: share.title, subtitle: share.subtitle, note: PillCopy.backTip))
    }

    @Test func backWithNothingKeptSaysSo() async {
        let k = Kit(heard: "back")
        await k.hold()
        #expect(k.pill.last == .nothing(heard: "back", message: PillCopy.nothingToGoBackTo))
        #expect(k.opener.opened.isEmpty)
    }

    @Test func aFailedOpenDoesNotChangeWhereBackGoes() async {
        let k = Kit(heard: "open YouTube")
        k.front.state = FrontState(card: .none, destination: notes)
        await k.hold()                                               // back now leads to Notes
        k.front.state = FrontState(card: .none, destination: .artifact(url: youTube))
        k.opener.error = .gone
        await k.hold()                                               // this open fails: nothing moved
        k.opener.error = nil
        k.transcriber.next = "back"
        await k.hold()
        #expect(k.opener.opened.last == notes)
    }

    @Test func aRememberedPhraseWhoseTargetClosedIsForgotten() async {
        let k = Kit(heard: phrase, cards: cards, outcome: .open(ideas))
        k.remembered.remember(phrase, cardKey: ideas.cardKey)
        k.opener.error = .gone
        await k.hold()
        #expect(k.remembered.cardKey(for: phrase) == nil)
        #expect(k.pill.last == .nothing(heard: phrase, message: PillCopy.noLongerOpen))
    }

    @Test func aGoneTargetDoesNotForgetAPhraseRememberedForAnotherCard() async {
        let k = Kit(heard: phrase, cards: cards, outcome: .open(ideas))
        k.remembered.remember(phrase, cardKey: share.cardKey)
        k.opener.error = .gone
        await k.hold()
        #expect(k.remembered.cardKey(for: phrase) == share.cardKey)
    }

    @Test func offersAndChoicesAreLogged() async {
        let k = await offering()
        #expect(k.logged.last?.outcome == "offered")
        #expect(k.logged.last?.heard == phrase)
        await k.coordinator.handle(.tapped)
        #expect(k.logged.last?.outcome == "opened")
        #expect(k.logged.last?.step == "choice")
        #expect(k.logged.last?.title == ideas.title)
        let left = await offering()
        left.scheduler.advance(by: 8)
        #expect(left.logged.last?.outcome == "left")
    }

    /// scripts/tally.py reads the lines the coordinator writes. This runs it on a real log to keep the two in step.
    @Test func theTallyScriptReadsWhatTheCoordinatorLogs() async throws {
        let k = Kit(heard: "open YouTube")
        k.front.state = FrontState(card: .none, destination: notes)
        await k.hold()
        k.transcriber.next = "back"
        await k.hold()
        let offered = await offering()
        try FileManager.default.copyItem(at: offered.logFile, to: k.logFile.appendingPathExtension("more"))
        let both = try String(contentsOf: k.logFile, encoding: .utf8) + String(contentsOf: offered.logFile, encoding: .utf8)
        try both.write(to: k.logFile, atomically: true, encoding: .utf8)

        let script = Fixture.dir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/tally.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, "--file", k.logFile.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        #expect(text.contains("wrong opens 1/2"))          // the open was followed by "back" at once
        #expect(text.contains("two-choice lists 1/2"))
        #expect(text.contains("opened: YouTube x1"))       // where each phrase went is listed, wrong opens included
    }
}
