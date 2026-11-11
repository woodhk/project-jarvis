import Foundation

/// The apps installed on this Mac, found by name in the usual folders.
public struct AppCatalog: Sendable {
    public static var defaultRoots: [URL] {
        ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            + [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
    }

    private static let makers = ["Google", "Microsoft", "Adobe"]

    /// "Chrome" for "Google Chrome": an app's name without its maker's, or nil when it has none.
    public static func shortName(_ name: String) -> String? {
        guard let maker = makers.first(where: { name.hasPrefix($0 + " ") }) else { return nil }
        let short = String(name.dropFirst(maker.count + 1))
        return short.isEmpty ? nil : short
    }
    /// Apps that do not live in an Applications folder but are asked for by name all the same.
    public static var defaultExtras: [URL] {
        [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)]
    }

    private let roots: [URL]
    private let extras: [URL]

    public init(roots: [URL] = AppCatalog.defaultRoots, extras: [URL] = AppCatalog.defaultExtras) {
        self.roots = roots
        self.extras = extras
    }

    /// One card per app directly inside a root. `aliases` maps a spoken name to an app's real name.
    public func apps(aliases: [String: String]) -> [AppCard] {
        var seen = Set<String>()
        var cards: [AppCard] = []
        let present = extras.filter { FileManager.default.fileExists(atPath: $0.path) }
        for (index, root) in (roots + [nil]).enumerated() {
            let entries = index < roots.count ? ((try? FileManager.default.contentsOfDirectory(at: root!, includingPropertiesForKeys: nil)) ?? []) : present
            for entry in entries where entry.pathExtension == "app" {
                let name = entry.deletingPathExtension().lastPathComponent
                guard seen.insert(name.lowercased()).inserted else { continue }
                var extra = aliases.filter { $0.value.lowercased() == name.lowercased() }.keys.sorted()
                // People say "Chrome", not "Google Chrome": an app is also known without its maker's name.
                if let short = Self.shortName(name), !extra.contains(where: { $0.lowercased() == short.lowercased() }) { extra.append(short) }
                cards.append(AppCard(name: name, aliases: extra, path: entry.path))
            }
        }
        return cards.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
