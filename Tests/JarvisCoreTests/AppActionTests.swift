import Foundation
import Testing
@testable import JarvisCore

/// "Close Spotify" hides the app and leaves it running. "Quit Spotify" quits it. Neither ever opens anything, and
/// only an app that was named can be closed or quit: never a session, a page or a website.
@Suite struct AppActionTests {
    var b: PickerBench
    var cards: CardSnapshot

    init() throws {
        b = try PickerBench()
        cards = b.cards
        cards.apps = [AppCard(name: "App Store", aliases: [], path: "/System/Applications/App Store.app"),
                      AppCard(name: "ChatGPT", aliases: [], path: "/Applications/ChatGPT.app"),
                      AppCard(name: "Google Chrome", aliases: ["Chrome"], path: "/Applications/Google Chrome.app"),
                      AppCard(name: "Spotify", aliases: [], path: "/Applications/Spotify.app"),
                      AppCard(name: "Terminal", aliases: [], path: "/System/Applications/Utilities/Terminal.app"),
                      AppCard(name: "Visual Studio Code", aliases: ["vs code"], path: "/Applications/Visual Studio Code.app")]
    }

    func app(_ name: String) -> Target { cards.target(for: cards.apps.first { $0.name == name }!) }
    func request(_ phrase: String) -> Outcome? { Picker.appRequest(Normalizer.words(phrase), in: cards) }

    @Test(arguments: [("close Spotify", "Spotify"), ("Close Spotify.", "Spotify"), ("oh, and then can you close Spotify", "Spotify"),
                      ("hide ChatGPT", "ChatGPT"), ("close the Spotify app", "Spotify"), ("can you close Chrome please", "Google Chrome"),
                      ("close Google Chrome", "Google Chrome"), ("okay now close the Spotify window for me", "Spotify"),
                      ("close VS Code", "Visual Studio Code"), ("close Terminal", "Terminal"), ("close the App Store", "App Store")])
    func closeHidesTheNamedApp(_ phrase: String, _ name: String) {
        #expect(request(phrase) == .app(AppRequest(action: .hide, target: app(name), ask: nil)))
    }

    @Test(arguments: [("quit Spotify", "Spotify"), ("Oh, can you quit Spotify?", "Spotify"), ("exit Spotify please", "Spotify"),
                      ("quit Chrome", "Google Chrome"), ("no, quit ChatGPT", "ChatGPT"), ("quit the App Store app", "App Store")])
    func quitQuitsTheNamedApp(_ phrase: String, _ name: String) {
        #expect(request(phrase) == .app(AppRequest(action: .quit, target: app(name), ask: nil)))
    }

    // A wrong quit costs more than a wrong open, so a name that was not heard exactly is asked about first.
    // A wrong close costs nothing: the app is only hidden.
    @Test func aNameThatWasNotHeardExactlyIsAskedAboutBeforeQuitting() {
        #expect(request("quit crime") == .app(AppRequest(action: .quit, target: app("Google Chrome"), ask: .unsureOfName)))
        #expect(request("quit spotifi") == .app(AppRequest(action: .quit, target: app("Spotify"), ask: .unsureOfName)))
        #expect(request("close crime") == .app(AppRequest(action: .hide, target: app("Google Chrome"), ask: nil)))
    }

    // Quitting Terminal or VS Code ends the Claude Code sessions that run inside it.
    @Test func quittingAnAppThatHoldsSessionsIsAskedAboutFirst() {
        let inTerminal = cards.sessions.filter { $0.host == .terminal }.count
        let inCode = cards.sessions.filter { $0.host == .vscode }.count
        #expect(inTerminal > 0 && inCode > 0)
        #expect(request("quit Terminal") == .app(AppRequest(action: .quit, target: app("Terminal"), ask: .endsSessions(inTerminal))))
        #expect(request("quit VS Code") == .app(AppRequest(action: .quit, target: app("Visual Studio Code"), ask: .endsSessions(inCode))))
        var none = cards
        none.sessions = []
        #expect(Picker.appRequest(["quit", "terminal"], in: none) == .app(AppRequest(action: .quit, target: app("Terminal"), ask: nil)))
    }

    @Test(arguments: ["close the artifact", "quit the pattern reel session", "close this session", "close YouTube", "quit", "close",
                      "close the insta session", "exit the interview notes page", "quit everything that is open right now on my mac"])
    func withoutAnAppNameNothingIsClosed(_ phrase: String) {
        guard case .appUnknown = request(phrase) else {
            Issue.record("\(phrase): \(String(describing: request(phrase)))")
            return
        }
    }

    @Test(arguments: ["open Spotify", "open the close rates session", "show all sessions", "back", "two", "open the artifact about quitting",
                      "what did I close", "open the session where we quit using redis", ""])
    func thesePhrasesAreNotAboutClosing(_ phrase: String) {
        #expect(request(phrase) == nil)
    }

    @Test func aRequestToCloseNeverReachesJevAndNeverOpens() async {
        let (p, jev, _) = b.make(kind: "app_or_website", session: ["s-gif": 1])
        #expect(await p.pick(transcript: "Can you close Spotify?", cards: cards, context: b.idle)
            == .app(AppRequest(action: .hide, target: app("Spotify"), ask: nil)))
        #expect(await p.pick(transcript: "quit the gif library session", cards: cards, context: b.idle) == .appUnknown(.quit))
        #expect(await p.pick(transcript: "quit Spotify", cards: cards, context: b.choosing)
            == .app(AppRequest(action: .quit, target: app("Spotify"), ask: nil)))
        #expect(jev.calls == 0)
        #expect(b.traces.last?.step == "control")
    }

    @Test func aRememberedPhraseDoesNotTurnACloseIntoAnOpen() async {
        let (p, _, _) = b.make(remembered: ["close spotify": app("Spotify").cardKey])
        #expect(await p.pick(transcript: "close Spotify", cards: cards, context: b.idle)
            == .app(AppRequest(action: .hide, target: app("Spotify"), ask: nil)))
    }

    @Test func aRequestToCloseStandsAlone() {
        #expect(FollowUp.joined(new: "no, quit Spotify", earlier: "open Spotify", secondsSince: 4, earlierOpened: true) == nil)
        #expect(FollowUp.joined(new: "close it", earlier: "open the tax return session", secondsSince: 4, earlierOpened: false) == nil)
    }

    // A question on the pill ("Quit Terminal?") can be answered by voice as well as by a tap or a key.
    @Test(arguments: ["yes", "Yeah.", "yes please", "do it", "go ahead", "Okay.", "yep", "sure", "confirm"])
    func yesTakesWhatIsOnShow(_ phrase: String) async {
        let (p, jev, _) = b.make()
        #expect(await p.pick(transcript: phrase, cards: cards, context: b.choosing) == .pickChoice(0))
        #expect(jev.calls == 0)
    }

    @Test(arguments: ["no", "No.", "cancel", "never mind", "nope", "no thanks", "don't"])
    func noSendsItAway(_ phrase: String) async {
        let (p, jev, _) = b.make()
        #expect(await p.pick(transcript: phrase, cards: cards, context: b.choosing) == .cancel)
        #expect(jev.calls == 0)
    }

    @Test func yesAndNoMeanNothingSpecialWithoutAQuestion() async {
        let (p, jev, _) = b.make(session: ["s-gif": 1], known: 0.01)
        #expect(await p.pick(transcript: "yes", cards: cards, context: b.idle) == .nothing)
        #expect(await p.pick(transcript: "no", cards: cards, context: b.idle) == .nothing)
        #expect(jev.calls == 2)
        // A longer sentence that starts with "no" is a correction, not an answer.
        #expect(Picker.saysNo(Normalizer.words("no, the artifact in Chrome")) == false)
        #expect(FollowUp.joined(new: "no", earlier: "quit terminal", secondsSince: 3, earlierOpened: false) == nil)
        #expect(FollowUp.joined(new: "yes", earlier: "quit terminal", secondsSince: 3, earlierOpened: false) == nil)
        #expect(FollowUp.joined(new: "no, the artifact in Chrome", earlier: "open the pattern page", secondsSince: 3, earlierOpened: true) != nil)
    }
}
