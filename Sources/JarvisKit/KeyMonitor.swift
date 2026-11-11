import CoreGraphics
import Foundation
import JarvisCore

/// Watches the fn (Globe) key through a listen-only event tap and reports hold events on the main thread.
/// It cannot change or block any key.
public final class KeyMonitor {
    private let onEvent: (HoldEvent) -> Void
    private var detector: HoldDetector
    private var fnBefore = false
    private var tap: CFMachPort?
    private var timer: Timer?

    public init(tapThreshold: TimeInterval = 0.3, maxHold: TimeInterval = 15, onEvent: @escaping (HoldEvent) -> Void) {
        self.onEvent = onEvent
        self.detector = HoldDetector(tapThreshold: tapThreshold, maxHold: maxHold)
    }

    /// Returns false when Input Monitoring is not granted (macOS is asked to prompt for it).
    public func start() -> Bool {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
            return false
        }
        let mask = CGEventMask((1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue))
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: keyMonitorCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        return true
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func tick() {
        if let event = detector.tick(at: now) { onEvent(event) }
    }

    /// When the event happened, in seconds since start-up: the same clock as `now`. Jarvis may get round to an event
    /// late (starting the microphone keeps the main thread busy), so the length of a hold is taken from the events.
    private func time(of event: CGEvent) -> TimeInterval {
        event.timestamp == 0 ? now : TimeInterval(event.timestamp) / 1_000_000_000
    }

    func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let flags = event.flags
            let fnNow = flags.contains(.maskSecondaryFn)
            let others = !flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty
            let input = HoldDetector.input(fnNow: fnNow, fnBefore: fnBefore, otherModifiers: others)
            fnBefore = fnNow
            if let input, let out = detector.handle(input, at: time(of: event)) { onEvent(out) }
        case .keyDown:
            if let out = detector.handle(.otherKeyDown, at: time(of: event)) { onEvent(out) }
        default:
            break
        }
    }
}

private func keyMonitorCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
