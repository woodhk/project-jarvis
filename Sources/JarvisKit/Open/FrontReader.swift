import AppKit
import JarvisCore

/// Works out what is in front when the key goes down: which card, if any, and how to come back to it.
public struct FrontReader: FrontReading {
    public typealias FrontApp = @Sendable () -> (bundleId: String, path: String)?

    private let runner: ScriptRunning
    private let bridge: VSCodeBridge?
    private let frontApp: FrontApp

    public init(runner: ScriptRunning, bridge: VSCodeBridge? = nil, frontApp: @escaping FrontApp = FrontReader.systemFrontApp) {
        self.runner = runner
        self.bridge = bridge
        self.frontApp = frontApp
    }

    public static let systemFrontApp: FrontApp = {
        guard let app = NSWorkspace.shared.frontmostApplication, let path = app.bundleURL?.path else { return nil }
        return (app.bundleIdentifier ?? "", path)
    }

    public func read(cards: CardSnapshot) async -> FrontState {
        let frontApp = self.frontApp
        guard let app = await MainActor.run(body: { frontApp() }) else { return FrontState(card: .none, destination: nil) }
        let appItself = FrontState(card: .none, destination: .app(path: app.path))
        switch app.bundleId {
        case "com.apple.Terminal":
            guard let tty = try? await runner.run(TerminalScripts.frontTTY), !tty.isEmpty else { return appItself }
            let session = cards.sessions.first { $0.host == .terminal && $0.tty == tty }
            return FrontState(card: session.map { .session(id: $0.id) } ?? .none, destination: .terminalTab(tty: tty))
        case "com.microsoft.VSCode":
            guard let bridge else { return appItself }
            let windows = await bridge.states()
            guard let window = windows.first(where: \.focused) ?? (windows.count == 1 ? windows.first : nil),
                  let active = window.activeShellPid else { return appItself }
            let session = cards.sessions.first { $0.host == .vscode && $0.shellPid == active }
            return FrontState(card: session.map { .session(id: $0.id) } ?? .none,
                              destination: .vscodeTerminal(shellPid: active, folderPath: session?.folderPath ?? window.folders.first ?? ""))
        case "com.google.Chrome":
            guard let address = try? await runner.run(ChromeScripts.frontURL), address.hasPrefix("http"),
                  let url = URL(string: address) else { return appItself }
            let artifact = cards.artifacts.first { card in
                let link = card.url.absoluteString
                return address == link || ["/", "?", "#"].contains { address.hasPrefix(link + $0) }
            }
            // For a page that is not a card, the address itself is the way back ("a tab whose address starts with this").
            return FrontState(card: artifact.map { .artifact(url: $0.url) } ?? .none, destination: .artifact(url: artifact?.url ?? url))
        default:
            return appItself
        }
    }
}
