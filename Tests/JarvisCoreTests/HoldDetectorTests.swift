import Testing
@testable import JarvisCore

@Test func longHoldEnds() {
    var d = HoldDetector()
    #expect(d.handle(.fnDown, at: 0) == .began)
    #expect(d.handle(.fnUp, at: 1.2) == .ended(duration: 1.2))
}

@Test func quickPressIsATap() {
    var d = HoldDetector()
    _ = d.handle(.fnDown, at: 0)
    #expect(d.handle(.fnUp, at: 0.2) == .tapped)
}

@Test func anotherKeyCancelsAndTheReleaseIsSilent() {
    var d = HoldDetector()
    _ = d.handle(.fnDown, at: 0)
    #expect(d.handle(.otherKeyDown, at: 0.5) == .cancelled)
    #expect(d.handle(.fnUp, at: 0.9) == nil)
}

@Test func strayEventsAreIgnored() {
    var d = HoldDetector()
    #expect(d.handle(.fnUp, at: 0) == nil)
    #expect(d.handle(.otherKeyDown, at: 0) == nil)
    _ = d.handle(.fnDown, at: 1)
    #expect(d.handle(.fnDown, at: 1.1) == nil)
}

@Test func aStuckKeyCancelsItself() {
    var d = HoldDetector()
    _ = d.handle(.fnDown, at: 0)
    #expect(d.tick(at: 14.9) == nil)
    #expect(d.tick(at: 15.1) == .cancelled)
    #expect(d.handle(.fnUp, at: 20) == nil)
}

@Test func fnWithAnotherModifierNeverStarts() {
    #expect(HoldDetector.input(fnNow: true, fnBefore: false, otherModifiers: false) == .fnDown)
    #expect(HoldDetector.input(fnNow: true, fnBefore: false, otherModifiers: true) == nil)
    #expect(HoldDetector.input(fnNow: true, fnBefore: true, otherModifiers: true) == .otherKeyDown)
    #expect(HoldDetector.input(fnNow: false, fnBefore: true, otherModifiers: false) == .fnUp)
    #expect(HoldDetector.input(fnNow: false, fnBefore: false, otherModifiers: true) == nil)
}
