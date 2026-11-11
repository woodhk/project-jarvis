import Foundation

/// The usual folders, known without being typed into the settings file. They are cards like websites, with a file
/// address in place of a web address, and open in Finder. Each is called "… folder", with the bare word as a second
/// name: where an app already has that word ("Music"), the app keeps it and "the music folder" still works.
public enum KnownFolders {
    public static func all(home: URL) -> [SiteCard] {
        func inHome(_ name: String) -> URL { home.appendingPathComponent(name, isDirectory: true) }
        let folders: [(String, [String], URL)] = [
            ("Downloads folder", ["Downloads"], inHome("Downloads")),
            ("Documents folder", ["Documents"], inHome("Documents")),
            ("Desktop folder", ["Desktop"], inHome("Desktop")),
            ("Pictures folder", ["Pictures"], inHome("Pictures")),
            ("Movies folder", ["Movies"], inHome("Movies")),
            ("Music folder", ["Music"], inHome("Music")),
            ("Applications folder", ["Applications", "Apps folder"], URL(fileURLWithPath: "/Applications", isDirectory: true)),
            ("Home folder", ["Home", "Home directory", "User folder"], home),
        ]
        return folders.map { SiteCard(name: $0.0, aliases: $0.1, url: $0.2, builtIn: true) }
    }
}
