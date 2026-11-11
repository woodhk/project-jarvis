import Foundation
import JarvisCore

public enum OpenError: Error, Equatable {
    /// The session ended or the tab was closed after it was picked.
    case gone
    /// macOS refused to let Jarvis control the named app.
    case notPermitted(String)
    case failed(String)
}

/// Brings one destination to the front. Returns an optional note for the pill.
public protocol Opening: Sendable {
    func open(_ destination: Destination) async throws -> String?
}

/// Runs AppleScript source and returns its result as text.
public protocol ScriptRunning: Sendable {
    func run(_ source: String) async throws -> String
}

/// What was in front when the key went down: the card, if it is one, and how to return there.
public struct FrontState: Equatable, Sendable {
    public var card: FrontCard
    public var destination: Destination?

    public init(card: FrontCard, destination: Destination?) {
        self.card = card
        self.destination = destination
    }
}

public protocol FrontReading: Sendable {
    func read(cards: CardSnapshot) async -> FrontState
}

/// For when nothing can be known about what is in front.
public struct NothingInFront: FrontReading {
    public init() {}
    public func read(cards: CardSnapshot) async -> FrontState { FrontState(card: .none, destination: nil) }
}

public protocol CardProviding: AnyObject {
    var snapshot: CardSnapshot { get }
    func refresh()
}

/// Sends each destination to the opener for its kind.
public struct CompositeOpener: Opening {
    private let terminal: Opening?
    private let vscode: Opening?
    private let chrome: Opening
    private let app: Opening
    private let folder: Opening

    public init(terminal: Opening?, vscode: Opening?, chrome: Opening, app: Opening, folder: Opening = FolderOpener()) {
        self.terminal = terminal
        self.vscode = vscode
        self.chrome = chrome
        self.app = app
        self.folder = folder
    }

    public func open(_ destination: Destination) async throws -> String? {
        switch destination {
        case .terminalTab:
            guard let terminal else { throw OpenError.failed("Terminal sessions cannot be opened yet.") }
            return try await terminal.open(destination)
        case .vscodeTerminal:
            guard let vscode else { throw OpenError.failed("VS Code sessions cannot be opened yet.") }
            return try await vscode.open(destination)
        case .site, .artifact:
            return try await chrome.open(destination)
        case .app:
            return try await app.open(destination)
        case .folder:
            return try await folder.open(destination)
        }
    }
}
