import Foundation

/// The choices the user has made: a spoken phrase → the card it meant. Kept in a small JSON file.
/// Phrases are compared without case, spaces or punctuation.
public final class RememberedStore: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private var table: [String: String]

    public init(file: URL) {
        self.file = file
        table = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
    }

    public func cardKey(for phrase: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return table[Normalizer.compact(phrase)]
    }

    public func remember(_ phrase: String, cardKey: String) {
        let key = Normalizer.compact(phrase)
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        table[key] = cardKey
        save()
    }

    public func forget(_ phrase: String) {
        lock.lock()
        defer { lock.unlock() }
        guard table.removeValue(forKey: Normalizer.compact(phrase)) != nil else { return }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(table).write(to: file, options: .atomic)
    }
}
