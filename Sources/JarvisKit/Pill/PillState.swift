import Foundation

public struct PillOption: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

public enum PillState: Equatable, Sendable {
    case hidden
    case listening
    case hint(String)
    case working(heard: String?)
    case opened(heard: String, title: String, subtitle: String, note: String)
    case choices(heard: String, options: [PillOption])
    /// Every open session, numbered. `more` is how many did not fit. `listening` is true while fn is held: the list
    /// stays on show so the number can still be read.
    case list(options: [PillOption], more: Int, listening: Bool)
    case nothing(heard: String, message: String)

    /// True for the states that are answered with a number key. Only then does the pill take the keyboard.
    public var takesKeys: Bool {
        switch self {
        case .choices, .list: return true
        default: return false
        }
    }
}

/// A key pressed while a numbered list is on show.
public enum PillKey: Equatable, Sendable {
    /// A digit from 1 to 9.
    case number(Int)
    /// Anything else, Escape included: the list closes.
    case other

    /// `plain` is false when command, control or option was held.
    public init(characters: String?, plain: Bool) {
        if plain, let characters, characters.count == 1, let digit = Int(characters), (1...9).contains(digit) {
            self = .number(digit)
        } else {
            self = .other
        }
    }
}

/// Every sentence the pill can show. No other wording is used anywhere.
public enum PillCopy {
    public static let listening = "Listening"
    public static let keepHolding = "Keep holding fn while you speak"
    public static let backTip = "Say “back” to return to where you were."
    public static let choicesTip = "Tap fn for 1, hold briefly for 2, or type the number.\nKeep holding fn to ask again."
    public static let oneChoiceTip = "Tap fn or type 1 to go ahead. Any other key cancels."
    public static let hidden = "Hidden. It is still running."
    public static func hiddenNote(_ app: String) -> String {
        "Say “open \(app)” to bring it back, or “quit \(app)” to quit it."
    }
    public static let quitDone = "Quit."
    public static func quitNote(_ app: String) -> String {
        "Say “open \(app)” to start it again."
    }
    public static let quitAsked = "Asked to quit."
    public static let quitAskedNote = "If it stays open, it is waiting for an answer from you."
    public static func notRunning(_ app: String) -> String {
        "\(app) is not open, so nothing changed."
    }
    public static let onlyApps = "Jarvis can close or quit an app by its name. Nothing changed."
    public static let couldNotClose = "That did not work, so nothing changed."
    public static func quitQuestion(_ app: String) -> String {
        "Quit \(app)?"
    }
    public static func endsSessions(_ count: Int) -> String {
        count == 1 ? "1 Claude Code session is running in it and would end." : "\(count) Claude Code sessions are running in it and would end."
    }
    public static let unsureOfName = "Not sure the name was heard right."
    public static let appInFront = "This is the app in front."
    public static let finderStays = "Finder is part of macOS and is not quit. Say “close Finder” to hide it."
    public static let listTitle = "Open sessions"
    public static let listTip = "Type a number, or hold fn and say it. Any other key closes the list."
    public static func moreNotShown(_ count: Int) -> String {
        "\(count) more not shown. These are the ones used most recently."
    }
    public static let noSessions = "No Claude Code session is open."
    public static let nothingMatches = "Nothing open matches that, so nothing moved. Say “show all sessions” to pick from a list."
    public static let unknownName = "No app or website with that name is known, so nothing moved. Add websites in the Jarvis menu: Edit websites."
    public static let leftAlone = "Left alone, so nothing moved."
    public static let remembered = "Remembered. Next time this phrase goes straight there."
    public static let didNotCatch = "Didn't catch that, so nothing moved."
    public static let noLongerOpen = "That is no longer open, so nothing moved."
    public static let folderGone = "That folder is not there now. If it is on a drive, plug the drive in."
    public static let nothingToGoBackTo = "Nothing to go back to."
    public static let couldNotOpen = "That could not be opened, so nothing moved."
    public static func notPermitted(_ app: String) -> String {
        "Jarvis is not allowed to control \(app). Allow it in System Settings, Privacy & Security, Automation."
    }
}

@MainActor public protocol PillShowing: AnyObject {
    func show(_ state: PillState)
}
