import Foundation

/// One change seen on the keyboard, already reduced to what matters for a hold of fn.
public enum KeyInput: Equatable {
    case fnDown, fnUp, otherKeyDown
}

public enum HoldEvent: Equatable {
    case began
    case ended(duration: TimeInterval)
    case tapped
    case cancelled
}

/// Turns key inputs into hold events. It holds no timers: the caller passes the time in.
public struct HoldDetector {
    private let tapThreshold: TimeInterval
    private let maxHold: TimeInterval
    private var heldSince: TimeInterval?

    public init(tapThreshold: TimeInterval = 0.3, maxHold: TimeInterval = 15) {
        self.tapThreshold = tapThreshold
        self.maxHold = maxHold
    }

    public var isHolding: Bool { heldSince != nil }

    public mutating func handle(_ input: KeyInput, at time: TimeInterval) -> HoldEvent? {
        switch (input, heldSince) {
        case (.fnDown, nil):
            heldSince = time
            return .began
        case (.fnUp, let since?):
            heldSince = nil
            let duration = time - since
            return duration < tapThreshold ? .tapped : .ended(duration: duration)
        case (.otherKeyDown, .some):
            heldSince = nil
            return .cancelled
        default:
            return nil
        }
    }

    /// Call regularly. A hold that outlives `maxHold` (a missed key-up, a keyboard that disconnected) cancels itself.
    public mutating func tick(at time: TimeInterval) -> HoldEvent? {
        guard let since = heldSince, time - since > maxHold else { return nil }
        heldSince = nil
        return .cancelled
    }

    /// Reduces a modifier-flags change to an input. fn pressed while another modifier is down never starts a hold.
    public static func input(fnNow: Bool, fnBefore: Bool, otherModifiers: Bool) -> KeyInput? {
        switch (fnNow, fnBefore) {
        case (true, false): return otherModifiers ? nil : .fnDown
        case (true, true): return otherModifiers ? .otherKeyDown : nil
        case (false, true): return .fnUp
        case (false, false): return nil
        }
    }
}
