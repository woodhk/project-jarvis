import AppKit
import JarvisCore
import SwiftUI

@MainActor final class SetupModel: ObservableObject {
    @Published var checks: [SetupCheck] = []
    @Published var checking = false
}

/// A plain list of what Jarvis needs: a tick, or what to do. "Check again" reads everything afresh.
struct SetupView: View {
    @ObservedObject var model: SetupModel
    let checkAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Jarvis setup").font(.title2).bold()
            ForEach(model.checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: check.status == .ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(check.status == .ok ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title).fontWeight(.medium)
                        if case .needsAction(let action) = check.status {
                            Text(action).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HStack {
                Button("Check again", action: checkAgain).disabled(model.checking)
                if model.checking { ProgressView().controlSize(.small) }
            }
        }
        .padding(22)
        .frame(width: 460, alignment: .leading)
    }
}

@MainActor public final class SetupWindow {
    private let probe: SetupProbe
    private let model = SetupModel()
    private var window: NSWindow?

    public init(probe: SetupProbe = SetupProbe()) {
        self.probe = probe
    }

    /// Opens the window (in front of other apps) with these checks, or reads them first when none are given.
    public func show(_ checks: [SetupCheck]? = nil) {
        if let checks { model.checks = checks } else { refresh(ask: false) }
        if window == nil {
            let hosting = NSHostingController(rootView: SetupView(model: model) { [weak self] in self?.refresh(ask: true) })
            let window = NSWindow(contentViewController: hosting)
            window.title = "Jarvis"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refresh(ask: Bool) {
        model.checking = true
        Task { @MainActor in
            model.checks = await probe.checks(askForAutomation: ask)
            model.checking = false
        }
    }
}
