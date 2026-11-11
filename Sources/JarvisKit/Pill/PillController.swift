import AppKit
import SwiftUI

/// The pill's panel. It takes the keyboard only while a numbered list is on show, and never makes Jarvis the app in
/// front: the window the user was in stays where it is and gets the keyboard back when the list goes.
final class KeyPanel: NSPanel {
    var takesKeys = false
    var onKey: ((PillKey) -> Void)?

    override var canBecomeKey: Bool { takesKeys }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard takesKeys, event.type == .keyDown else { return super.sendEvent(event) }
        if event.isARepeat { return }
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        onKey?(PillKey(characters: event.charactersIgnoringModifiers, plain: plain))
    }
}

/// Owns the panel that shows the pill. The panel never moves another window, and takes the keyboard only for a list.
@MainActor public final class PillController: PillShowing {
    private let model = PillModel()
    private let panel: KeyPanel
    private let hosting: NSHostingController<PillView>

    /// Called with each key pressed while a numbered list is on show.
    public var onKey: ((PillKey) -> Void)? {
        get { panel.onKey }
        set { panel.onKey = newValue }
    }

    public init() {
        hosting = NSHostingController(rootView: PillView(model: model))
        hosting.sizingOptions = []
        panel = Self.makePanel()
        panel.contentViewController = hosting
    }

    private static func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Makes a panel like the pill's, invisible, and reports whether macOS lets it take the keyboard while another
    /// app stays in front. For checking a new build; it is over in a fraction of a second.
    public static func canTakeKeys() -> Bool {
        let panel = makePanel()
        panel.alphaValue = 0
        panel.takesKeys = true
        panel.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let isKey = panel.isKeyWindow
        panel.orderOut(nil)
        return isKey
    }

    /// How long two choices wait for an answer (the bar under them empties over this time).
    public var choiceSeconds: TimeInterval {
        get { model.choiceSeconds }
        set { model.choiceSeconds = newValue }
    }

    /// How long the list of all sessions waits for a number.
    public var listSeconds: TimeInterval {
        get { model.listSeconds }
        set { model.listSeconds = newValue }
    }

    public func show(_ state: PillState) {
        let hadKeys = panel.takesKeys
        panel.takesKeys = state.takesKeys
        guard state != .hidden else {
            model.state = state
            panel.orderOut(nil)                 // the window the user was in gets the keyboard back
            return
        }
        place(state)
        if state.takesKeys {
            panel.makeKeyAndOrderFront(nil)     // a non-activating panel: the app in front stays in front
        } else {
            if hadKeys, panel.isKeyWindow { panel.orderOut(nil) }       // hand the keyboard back before showing the result
            panel.orderFrontRegardless()
        }
    }

    /// Takes the state in and sizes the panel for it, without showing it. Returns the panel's new size.
    @discardableResult
    func place(_ state: PillState) -> CGSize {
        if state.takesKeys, model.state != state { model.choiceShownAt = Date() }
        model.state = state
        // Measured on a fresh copy of the view: the view on show takes a new state in only on the next turn of the
        // run loop, so measuring it now would give the size of the state before.
        let size = Self.size(for: state)
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let origin = CGPoint(x: screen.midX - size.width / 2, y: screen.minY + 14)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        return panel.frame.size
    }

    /// The size a pill needs for a state: as wide as its content, at most `PillView.maxWidth`.
    static func size(for state: PillState) -> CGSize {
        let fresh = PillModel()
        fresh.state = state
        return NSHostingController(rootView: PillView(model: fresh)).sizeThatFits(in: CGSize(width: PillView.maxWidth, height: 600))
    }
}

extension PillController {
    /// Draws one pill state into a PNG without showing anything on screen. Used to check the pill's look.
    /// It goes through the same hosting view and the same sizing as the real panel.
    public static func renderPNG(_ state: PillState) -> Data? {
        let model = PillModel()
        model.state = state
        let hosting = NSHostingController(rootView: PillView(model: model))
        hosting.sizingOptions = []
        let size = Self.size(for: state)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentViewController = hosting
        window.setContentSize(size)
        hosting.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))          // let SwiftUI take the view in
        guard let bitmap = hosting.view.bitmapImageRepForCachingDisplay(in: hosting.view.bounds) else { return nil }
        hosting.view.cacheDisplay(in: hosting.view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}
