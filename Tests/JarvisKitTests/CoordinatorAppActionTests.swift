import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

/// "Close Spotify" hides the app; "quit Spotify" quits it. A quit that could cost something waits for a yes.
@MainActor @Suite struct CoordinatorAppActionTests {
    nonisolated static let spotifyPath = "/Applications/Spotify.app"
    nonisolated static let terminalPath = "/System/Applications/Utilities/Terminal.app"
    let spotify = Target(destination: .app(path: spotifyPath), title: "Spotify", subtitle: "app", cardKey: "app:" + spotifyPath)
    let terminal = Target(destination: .app(path: terminalPath), title: "Terminal", subtitle: "app", cardKey: "app:" + terminalPath)

    func kit(_ heard: String, _ outcome: Outcome, running: Set<String> = [spotifyPath, terminalPath]) -> Kit {
        let k = Kit(heard: heard, outcome: outcome)
        k.apps.running = running
        return k
    }

    func asking(_ ask: AppRequest.Ask = .endsSessions(2)) async -> Kit {
        let k = kit("quit terminal", .app(AppRequest(action: .quit, target: terminal, ask: ask)))
        await k.hold()
        return k
    }

    func question(_ ask: AppRequest.Ask = .endsSessions(2)) -> PillState {
        let why = ask == .unsureOfName ? PillCopy.unsureOfName : PillCopy.endsSessions(2)
        return .choices(heard: "quit terminal", options: [PillOption(title: PillCopy.quitQuestion("Terminal"), subtitle: why)])
    }

    @Test func closeHidesARunningAppAndSaysItStillRuns() async {
        let k = kit("close Spotify", .app(AppRequest(action: .hide, target: spotify, ask: nil)))
        await k.hold()
        #expect(k.apps.hidden == [Self.spotifyPath])
        #expect(k.apps.quit.isEmpty)
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == .opened(heard: "close Spotify", title: "Spotify", subtitle: PillCopy.hidden, note: PillCopy.hiddenNote("Spotify")))
        #expect(k.logged.last?.outcome == "hidden")
        #expect(k.logged.last?.title == "Spotify")
        #expect(k.remembered.cardKey(for: "close Spotify") == nil)
    }

    @Test func quitQuitsARunningApp() async {
        let k = kit("quit Spotify", .app(AppRequest(action: .quit, target: spotify, ask: nil)))
        await k.hold()
        #expect(k.apps.quit == [Self.spotifyPath])
        #expect(k.apps.hidden.isEmpty)
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == .opened(heard: "quit Spotify", title: "Spotify", subtitle: PillCopy.quitDone, note: PillCopy.quitNote("Spotify")))
        #expect(k.logged.last?.outcome == "quit")
    }

    @Test func anAppThatDoesNotGoAwayIsReportedAsAsked() async {
        let k = kit("quit Spotify", .app(AppRequest(action: .quit, target: spotify, ask: nil)))
        k.apps.quitResult = .asked                                  // it is showing "save changes?"
        await k.hold()
        #expect(k.pill.last == .opened(heard: "quit Spotify", title: "Spotify", subtitle: PillCopy.quitAsked, note: PillCopy.quitAskedNote))
    }

    @Test func anAppThatIsNotOpenIsLeftAlone() async {
        let k = kit("quit Spotify", .app(AppRequest(action: .quit, target: spotify, ask: nil)), running: [])
        await k.hold()
        #expect(k.apps.quit.isEmpty)
        #expect(k.pill.last == .nothing(heard: "quit Spotify", message: PillCopy.notRunning("Spotify")))
        let asked = kit("quit terminal", .app(AppRequest(action: .quit, target: terminal, ask: .endsSessions(2))), running: [])
        await asked.hold()
        #expect(asked.pill.last == .nothing(heard: "quit terminal", message: PillCopy.notRunning("Terminal")))      // no question about an app that is not open
    }

    @Test func aQuitThatWouldEndSessionsWaitsForAYes() async {
        let k = await asking()
        #expect(k.pill.last == question())
        #expect(k.apps.quit.isEmpty)
        #expect(k.logged.last?.outcome == "offered")
        await k.coordinator.handle(.tapped)
        #expect(k.apps.quit == [Self.terminalPath])
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == .opened(heard: "quit terminal", title: "Terminal", subtitle: PillCopy.quitDone, note: PillCopy.quitNote("Terminal")))
        #expect(k.logged.last?.outcome == "quit")
        #expect(k.remembered.cardKey(for: "quit terminal") == nil)
    }

    @Test func typingOneIsAYesAndAnyOtherKeyIsANo() async {
        let yes = await asking()
        await yes.coordinator.typed(.number(1))
        #expect(yes.apps.quit == [Self.terminalPath])
        let no = await asking()
        await no.coordinator.typed(.other)
        #expect(no.apps.quit.isEmpty)
        #expect(no.pill.last == .hidden)
        await no.coordinator.handle(.tapped)                        // the question is gone: a tap is only a tap again
        #expect(no.apps.quit.isEmpty)
    }

    @Test func aQuestionLeftAloneQuitsNothing() async {
        let k = await asking()
        k.scheduler.advance(by: 8.1)
        #expect(k.apps.quit.isEmpty)
        #expect(k.pill.last == .nothing(heard: "quit terminal", message: PillCopy.leftAlone))
    }

    @Test func holdingFnWithoutAWordIsNotAYes() async {
        let k = await asking()
        k.recorder.samples = [Float](repeating: 0, count: 8000)
        await k.hold(for: 0.5)
        #expect(k.apps.quit.isEmpty)
        #expect(k.pill.last == question())
    }

    @Test func aNameThatWasNotHeardExactlyIsAskedAbout() async {
        let k = await asking(.unsureOfName)
        #expect(k.pill.last == question(.unsureOfName))
        #expect(k.apps.quit.isEmpty)
    }

    @Test func aCloseThatFailsSaysSo() async {
        let k = kit("close Spotify", .app(AppRequest(action: .hide, target: spotify, ask: nil)))
        k.apps.hideResult = .failed
        await k.hold()
        #expect(k.pill.last == .nothing(heard: "close Spotify", message: PillCopy.couldNotClose))
        #expect(k.logged.last?.outcome == "failed")
    }

    @Test func closingSomethingThatIsNotAnAppSaysWhatCanBeClosed() async {
        let k = kit("close the artifact", .appUnknown(.hide))
        await k.hold()
        #expect(k.pill.last == .nothing(heard: "close the artifact", message: PillCopy.onlyApps))
        #expect(k.apps.hidden.isEmpty && k.apps.quit.isEmpty && k.opener.opened.isEmpty)
    }

    @Test func aQuestionWithOneAnswerSaysHowToAnswerIt() {
        let one = PillController.size(for: .choices(heard: "quit terminal", options: [PillOption(title: "Quit Terminal?", subtitle: PillCopy.endsSessions(2))]))
        #expect(one.height > 60 && one.width <= PillView.maxWidth)
        #expect(PillCopy.oneChoiceTip.contains("1"))
        #expect(!PillCopy.oneChoiceTip.contains("2"))
    }

    @Test func sayingYesQuitsAndSayingNoDoesNot() async {
        let yes = await asking()
        yes.transcriber.next = "Yes."
        await yes.hold(for: 0.6)
        #expect(yes.apps.quit == [Self.terminalPath])
        let no = await asking()
        no.transcriber.next = "No."
        await no.hold(for: 0.6)
        #expect(no.apps.quit.isEmpty)
        #expect(no.pill.last == .hidden)
        #expect(no.logged.last?.outcome == "left")
        #expect(no.opener.opened.isEmpty)
    }

    @Test func aNameThatIsNotKnownSaysHowToAddIt() async {
        let k = kit("open Flibbertigibbet", .unknownName)
        await k.hold()
        #expect(k.pill.last == .nothing(heard: "open Flibbertigibbet", message: PillCopy.unknownName))
        #expect(k.opener.opened.isEmpty)
        #expect(k.logged.last?.outcome == "nothing")
    }

    // MARK: "Close it", Finder and folders (sixth hand test)

    @Test func closeItHidesTheAppInFront() async {
        let k = kit("can you close it", .appInFront(.hide))
        k.apps.front = ("Spotify", Self.spotifyPath)
        await k.hold()
        #expect(k.apps.hidden == [Self.spotifyPath])
        #expect(k.pill.last == .opened(heard: "can you close it", title: "Spotify", subtitle: PillCopy.hidden, note: PillCopy.hiddenNote("Spotify")))
    }

    @Test func quitItNamesTheAppAndWaitsForAYes() async {
        let k = kit("quit it", .appInFront(.quit))
        k.apps.front = ("Spotify", Self.spotifyPath)
        await k.hold()
        #expect(k.apps.quit.isEmpty)
        #expect(k.pill.last == .choices(heard: "quit it", options: [PillOption(title: PillCopy.quitQuestion("Spotify"), subtitle: PillCopy.appInFront)]))
        await k.coordinator.handle(.tapped)
        #expect(k.apps.quit == [Self.spotifyPath])
    }

    @Test func quitItSaysWhenSessionsWouldEnd() async throws {
        let cards = try Fixture.cards()
        let inTerminal = cards.sessions.filter { $0.host == .terminal }.count
        let k = Kit(heard: "quit this", cards: cards, outcome: .appInFront(.quit))
        k.apps.running = [Self.terminalPath]
        k.apps.front = ("Terminal", Self.terminalPath)
        await k.hold()
        #expect(inTerminal > 0)
        #expect(k.pill.last == .choices(heard: "quit this", options: [PillOption(title: PillCopy.quitQuestion("Terminal"),
                                                                                    subtitle: PillCopy.endsSessions(inTerminal))]))
        #expect(k.apps.quit.isEmpty)
    }

    @Test func closeItWithNothingKnownInFrontChangesNothing() async {
        let k = kit("close it", .appInFront(.hide))
        await k.hold()
        #expect(k.apps.hidden.isEmpty)
        #expect(k.pill.last == .nothing(heard: "close it", message: PillCopy.onlyApps))
    }

    @Test func finderIsHiddenButNeverQuit() async {
        let path = "/System/Library/CoreServices/Finder.app"
        let finder = Target(destination: .app(path: path), title: "Finder", subtitle: "app", cardKey: "app:" + path)
        let quit = kit("quit Finder", .app(AppRequest(action: .quit, target: finder, ask: nil)), running: [path])
        await quit.hold()
        #expect(quit.apps.quit.isEmpty)
        #expect(quit.pill.last == .nothing(heard: "quit Finder", message: PillCopy.finderStays))
        let front = kit("quit it", .appInFront(.quit), running: [path])
        front.apps.front = ("Finder", path)
        await front.hold()
        #expect(front.apps.quit.isEmpty)
        #expect(front.pill.last == .nothing(heard: "quit it", message: PillCopy.finderStays))
        let close = kit("close Finder", .app(AppRequest(action: .hide, target: finder, ask: nil)), running: [path])
        await close.hold()
        #expect(close.apps.hidden == [path])
    }

    @Test func aFolderGoesToFinderNotToChrome() async throws {
        let chrome = FakeOpener(), app = FakeOpener(), folder = FakeOpener()
        let opener = CompositeOpener(terminal: nil, vscode: nil, chrome: chrome, app: app, folder: folder)
        _ = try await opener.open(.folder(path: "/Users/sam/Downloads"))
        #expect(folder.opened == [.folder(path: "/Users/sam/Downloads")])
        #expect(chrome.opened.isEmpty && app.opened.isEmpty)
    }

    @Test func aFolderThatIsNotThereIsReportedAsGone() async {
        await #expect(throws: OpenError.gone) {
            _ = try await FolderOpener().open(.folder(path: "/nonexistent/jarvis-test-\(UUID().uuidString)"))
        }
    }
}
