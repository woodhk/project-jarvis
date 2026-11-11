import Foundation
import Testing
@testable import JarvisCore

/// "Show all sessions": every open session as a numbered list, for when the name will not come to mind.
@Suite struct SessionListTests {
    var b: PickerBench
    init() throws { b = try PickerBench() }

    @Test(arguments: ["show all sessions", "Show all sessions.", "list sessions", "show me my sessions", "what sessions are open",
                      "show the list", "show all", "show me everything", "show all the terminals", "sessions", "what's open",
                      "show all the Claude sessions that are currently in session", "list all the open terminals", "show me the options",
                      "can you show me all my sessions please", "show sessions"])
    func thesePhrasesAskForTheList(_ phrase: String) {
        #expect(Picker.asksForList(Normalizer.words(phrase)))
    }

    @Test(arguments: ["open the session", "open the insta session", "show me the terminal", "open terminal", "open the shopping list session",
                      "show the pattern sessions", "open youtube", "back", "two", "open the artifact", "show me the gif library", "all",
                      "list", "what is the pattern reel session about", ""])
    func thesePhrasesDoNot(_ phrase: String) {
        #expect(!Picker.asksForList(Normalizer.words(phrase)))
    }

    @Test func theListHoldsEverySessionNewestFirst() async {
        var cards = b.cards
        let now = Date()
        for index in cards.sessions.indices { cards.sessions[index].lastActive = nil }
        let ids = cards.sessions.map(\.id)
        cards.sessions[2].lastActive = now.addingTimeInterval(-10)
        cards.sessions[4].lastActive = now.addingTimeInterval(-300)
        cards.sessions[0].lastActive = now.addingTimeInterval(-4000)
        let (p, jev, _) = b.make()
        let expected = [ids[2], ids[4], ids[0], ids[1], ids[3], ids[5]].map { id in cards.target(for: cards.sessions.first { $0.id == id }!) }
        #expect(await p.pick(transcript: "show all sessions", cards: cards, context: b.idle) == .list(expected))
        #expect(await p.pick(transcript: "show all sessions", cards: cards, context: b.front(ids[2])) == .list(expected))
        #expect(await p.pick(transcript: "show all sessions", cards: cards, context: b.choosing) == .list(expected))
        #expect(jev.calls == 0)
        #expect(b.traces.last?.step == "control")
    }

    @Test func aListIsNeverLongerThanNine() async {
        var cards = b.cards
        let one = cards.sessions[0]
        cards.sessions = (0..<12).map { n in
            var card = one
            card.id = "s-\(n)"
            card.label = "session \(n)"
            return card
        }
        let (p, _, _) = b.make()
        guard case .list(let targets) = await p.pick(transcript: "list sessions", cards: cards, context: b.idle) else {
            Issue.record("not a list")
            return
        }
        #expect(targets.map(\.title) == (0..<9).map { "session \($0)" })
    }

    @Test func withNoSessionsTheListIsEmpty() async {
        let (p, _, _) = b.make()
        #expect(await p.pick(transcript: "show all sessions", cards: CardSnapshot(), context: b.idle) == .list([]))
    }

    @Test(arguments: [("one", 0), ("1", 0), ("the first one", 0), ("two", 1), ("to", 1), ("too", 1), ("number 2", 1), ("the second one", 1),
                      ("three", 2), ("3", 2), ("the third one", 2), ("number three", 2), ("four", 3), ("4", 3), ("for", 3), ("option 4", 3),
                      ("five", 4), ("fifth", 4), ("six", 5), ("6", 5), ("seven", 6), ("seventh", 6), ("eight", 7), ("8", 7),
                      ("nine", 8), ("9th", 8), ("number nine please", 8), ("#4", 3)])
    func aSpokenNumberIsAChoice(_ phrase: String, _ index: Int) {
        #expect(Picker.choiceIndex(Normalizer.words(phrase)) == index)
    }

    @Test(arguments: ["two or three", "open the one for youtube", "ten", "0", "for the", "open youtube", "", "the one two three song",
                      "three four"])
    func theseAreNotAChoice(_ phrase: String) {
        #expect(Picker.choiceIndex(Normalizer.words(phrase)) == nil)
    }

    @Test func aRequestForTheListIsNeverJoinedToTheRequestBefore() {
        #expect(FollowUp.joined(new: "show all sessions", earlier: "open the tax return session", secondsSince: 5, earlierOpened: false) == nil)
        #expect(FollowUp.joined(new: "four", earlier: "open the tax return session", secondsSince: 5, earlierOpened: false) == nil)
    }

    @Test func aCardWithoutATimeStillLoads() throws {
        let data = try JSONEncoder().encode(b.cards.sessions[0])
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["lastActive"] = nil
        let card = try JSONDecoder().decode(SessionCard.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(card.lastActive == nil)
        #expect(card.id == b.cards.sessions[0].id)
    }

    @Test(arguments: [(0.0, "just now"), (59.0, "just now"), (60.0, "1 min ago"), (3540.0, "59 min ago"), (3600.0, "1 h ago"),
                      (86_399.0, "23 h ago"), (86_400.0, "1 d ago"), (400_000.0, "4 d ago"), (-30.0, "just now")])
    func timeSinceIsSaidShortly(_ seconds: Double, _ text: String) {
        #expect(Ago.short(seconds) == text)
    }
}
