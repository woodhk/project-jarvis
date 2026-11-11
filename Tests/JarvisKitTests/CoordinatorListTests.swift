import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

/// "Show all sessions": a numbered list of every open session, answered by typing or saying a number.
@MainActor @Suite struct CoordinatorListTests {
    var cards: CardSnapshot
    let targets: [Target]
    let phrase = "show all sessions"
    let youTube = URL(string: "https://www.youtube.com/")!

    init() throws {
        cards = try Fixture.cards()
        for index in cards.sessions.indices { cards.sessions[index].lastActive = nil }
        cards.sessions[0].lastActive = Date().addingTimeInterval(-300)
        cards.sessions[1].lastActive = Date().addingTimeInterval(-7200)
        let snapshot = cards
        targets = snapshot.sessions.map { snapshot.target(for: $0) }
    }

    /// A kit that has just been asked for the list.
    func listing(_ shown: [Target]? = nil) async -> Kit {
        let k = Kit(heard: phrase, cards: cards, outcome: .list(shown ?? targets))
        await k.hold()
        return k
    }

    func rows(listening: Bool = false) -> PillState {
        var options = targets.map { PillOption(title: $0.title, subtitle: $0.subtitle) }
        options[0].subtitle += " · 5 min ago"
        options[1].subtitle += " · 2 h ago"
        return .list(options: options, more: 0, listening: listening)
    }

    @Test func theListShowsEverySessionAndWhenItWasLastUsed() async {
        let k = await listing()
        #expect(k.pill.last == rows())
        #expect(k.opener.opened.isEmpty)
        #expect(k.logged.last?.outcome == "listed")
        #expect(k.logged.last?.title == "6 sessions")
    }

    @Test func sayingANumberOpensThatSession() async {
        let k = await listing()
        k.transcriber.next = "Four."
        await k.hold(for: 0.5)
        #expect(k.opener.opened == [targets[3].destination])
        #expect(k.pill.last == .opened(heard: phrase, title: targets[3].title, subtitle: targets[3].subtitle, note: PillCopy.backTip))
        #expect(k.remembered.cardKey(for: phrase) == nil)
        #expect(k.logged.last?.step == "choice")
    }

    @Test func typingANumberOpensThatSession() async {
        let k = await listing()
        await k.coordinator.typed(.number(3))
        #expect(k.opener.opened == [targets[2].destination])
        #expect(k.pill.last == .opened(heard: phrase, title: targets[2].title, subtitle: targets[2].subtitle, note: PillCopy.backTip))
    }

    @Test func aNumberWithNoSuchRowKeepsTheList() async {
        let k = await listing()
        await k.coordinator.typed(.number(9))
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == rows())
        k.transcriber.next = "Eight."
        await k.hold(for: 0.5)
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == rows())
    }

    @Test func anyOtherKeyClosesTheList() async {
        let k = await listing()
        await k.coordinator.typed(.other)
        #expect(k.pill.last == .hidden)
        #expect(k.opener.opened.isEmpty)
        #expect(k.logged.last?.outcome == "left")
        await k.coordinator.typed(.number(1))                       // the list is gone: a number means nothing now
        #expect(k.opener.opened.isEmpty)
        k.scheduler.advance(by: 30)
        #expect(k.pill.last == .hidden)
    }

    @Test func aTapDoesNotPickFromTheList() async {
        let k = await listing()
        await k.coordinator.handle(.tapped)
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == rows())
    }

    @Test func aSilentHoldDoesNotPickFromTheList() async {
        let k = await listing()
        k.recorder.samples = [Float](repeating: 0, count: 8000)
        await k.hold(for: 0.5)
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.last == rows())
    }

    @Test func theListStaysOnShowWhileFnIsHeld() async {
        let k = await listing()
        await k.coordinator.handle(.began)
        #expect(k.pill.last == rows(listening: true))
        k.scheduler.advance(by: 3)                                  // long enough to read the list and find the number
        #expect(k.pill.last == rows(listening: true))
        k.transcriber.next = "2"
        await k.coordinator.handle(.ended(duration: 3))
        #expect(k.opener.opened == [targets[1].destination])
    }

    @Test func theListWaitsLongerThanTwoChoices() async {
        let k = await listing()
        k.scheduler.advance(by: 19.9)
        #expect(k.pill.last == rows())
        k.scheduler.advance(by: 0.2)
        #expect(k.pill.last == .nothing(heard: phrase, message: PillCopy.leftAlone))
        #expect(k.opener.opened.isEmpty)
    }

    @Test func aNewRequestReplacesTheList() async {
        let k = await listing()
        k.picker.outcome = nil
        k.transcriber.next = "open YouTube"
        await k.hold(for: 2)
        #expect(k.opener.opened == [.site(url: youTube)])
    }

    @Test func sessionsThatDoNotFitAreCounted() async {
        var many = cards
        many.sessions += (0..<6).map { n in
            var card = cards.sessions[0]
            card.id = "extra-\(n)"
            return card
        }
        let k = Kit(heard: phrase, cards: many, outcome: .list(Array(targets.prefix(5))))
        await k.hold()
        guard case .list(let options, let more, _) = k.pill.last else {
            Issue.record("not a list")
            return
        }
        #expect(options.count == 5)
        #expect(more == 7)
    }

    @Test func withNoSessionOpenItSaysSo() async {
        let k = await listing([])
        #expect(k.pill.last == .nothing(heard: phrase, message: PillCopy.noSessions))
        #expect(k.logged.last?.outcome == "nothing")
    }

    @Test func aTypedNumberAnswersTwoChoicesToo() async {
        let k = Kit(heard: "open the insta session", cards: cards, outcome: .choices([targets[0], targets[3]], rememberable: true))
        await k.hold()
        await k.coordinator.typed(.number(2))
        #expect(k.opener.opened == [targets[3].destination])
        #expect(k.remembered.cardKey(for: "open the insta session") == targets[3].cardKey)
    }

    @Test func aKeyWithNothingOnShowDoesNothing() async {
        let k = Kit(heard: "open YouTube")
        await k.coordinator.typed(.number(1))
        await k.coordinator.typed(.other)
        #expect(k.opener.opened.isEmpty)
        #expect(k.pill.states.isEmpty)
    }

    @Test func onlyAPlainDigitIsANumber() {
        #expect(PillKey(characters: "3", plain: true) == .number(3))
        #expect(PillKey(characters: "9", plain: true) == .number(9))
        #expect(PillKey(characters: "0", plain: true) == .other)
        #expect(PillKey(characters: "3", plain: false) == .other)          // with command, control or option held
        #expect(PillKey(characters: "a", plain: true) == .other)
        #expect(PillKey(characters: "\u{1B}", plain: true) == .other)
        #expect(PillKey(characters: nil, plain: true) == .other)
    }

    @Test func onlyListsTakeTheKeyboard() {
        let option = PillOption(title: "a", subtitle: "b")
        #expect(PillState.list(options: [option], more: 0, listening: false).takesKeys)
        #expect(PillState.choices(heard: "x", options: [option, option]).takesKeys)
        #expect(!PillState.listening.takesKeys)
        #expect(!PillState.opened(heard: "x", title: "a", subtitle: "b", note: "").takesKeys)
        #expect(!PillState.nothing(heard: "x", message: "y").takesKeys)
        #expect(!PillState.hidden.takesKeys)
    }

    @Test func theListPillIsDrawnAtASizeThatHoldsNineRows() {
        let options = (1...9).map { PillOption(title: "Session number \($0) with a fairly long name", subtitle: "Terminal · some-folder · 5 min ago") }
        let nine = PillController.size(for: .list(options: options, more: 3, listening: false))
        let two = PillController.size(for: .list(options: Array(options.prefix(2)), more: 0, listening: false))
        #expect(nine.height > two.height + 150)
        #expect(nine.height < 600)
        #expect(nine.width <= PillView.maxWidth)
        // Holding fn must not make the list jump: the same rows take the same room whether or not it is listening.
        #expect(PillController.size(for: .list(options: options, more: 3, listening: true)) == nine)
    }
}
