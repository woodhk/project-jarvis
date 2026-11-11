import Foundation
import Testing
@testable import JarvisCore

/// From the third hand test: after "open the pattern selection artifact" went wrong, the user said "no, the artifact
/// in Chrome" and expected Jarvis to remember what the talk was about.
@Suite struct FollowUpTests {
    let earlier = "open the pattern selection artifact"

    @Test func aCorrectionIsJoinedToTheRequestBefore() {
        #expect(FollowUp.joined(new: "no, the artifact in chrome", earlier: earlier, secondsSince: 12, earlierOpened: true)
            == "open the pattern selection artifact. no, the artifact in chrome")
        #expect(FollowUp.joined(new: "Know the artifact in Chrome.", earlier: earlier, secondsSince: 12, earlierOpened: true) != nil)   // "no" as the speech model wrote it
        #expect(FollowUp.joined(new: "I meant the terminal", earlier: earlier, secondsSince: 5, earlierOpened: true) != nil)
        #expect(FollowUp.joined(new: "not that one, the session", earlier: earlier, secondsSince: 5, earlierOpened: true) != nil)
    }

    @Test func aPhraseWithNoWordOfItsOwnContinuesARequestThatDidNotOpen() {
        #expect(FollowUp.joined(new: "open the artifact", earlier: earlier, secondsSince: 10, earlierOpened: false)
            == "open the pattern selection artifact. open the artifact")
        #expect(FollowUp.joined(new: "open the artifact", earlier: earlier, secondsSince: 10, earlierOpened: true) == nil)   // then what is in front decides
    }

    @Test func aNewRequestStandsAlone() {
        #expect(FollowUp.joined(new: "open YouTube", earlier: earlier, secondsSince: 5, earlierOpened: false) == nil)
        #expect(FollowUp.joined(new: "open the gif library session", earlier: earlier, secondsSince: 5, earlierOpened: false) == nil)
        #expect(FollowUp.joined(new: "no, the artifact in chrome", earlier: earlier, secondsSince: 45, earlierOpened: false) == nil)   // too long ago
        #expect(FollowUp.joined(new: "no, the artifact", earlier: nil, secondsSince: 0, earlierOpened: false) == nil)
        for control in ["back", "Go back.", "two", "the second one", "2"] {
            #expect(FollowUp.joined(new: control, earlier: earlier, secondsSince: 5, earlierOpened: false) == nil, "\(control)")
        }
    }
}
