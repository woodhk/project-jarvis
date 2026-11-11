import Foundation

/// Every file location the app uses. All are under the real home folder unless JARVIS_HOME is set.
public enum Paths {
    public static var home: URL {
        if let override = ProcessInfo.processInfo.environment["JARVIS_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var appSupport: URL { home.appendingPathComponent("Library/Application Support/Jarvis", isDirectory: true) }
    public static var modelFile: URL { appSupport.appendingPathComponent("models/ggml-small.en.bin") }
    public static var configFile: URL { appSupport.appendingPathComponent("config.json") }
    public static var rememberedFile: URL { appSupport.appendingPathComponent("remembered.json") }
    public static var artifactCache: URL { appSupport.appendingPathComponent("artifact-index.json") }
    public static var folderCache: URL { appSupport.appendingPathComponent("folder-index.json") }
    public static var vscodeSockets: URL { appSupport.appendingPathComponent("vscode", isDirectory: true) }
    public static var logFile: URL { home.appendingPathComponent("Library/Logs/Jarvis/events.jsonl") }
    public static var claudeDir: URL { home.appendingPathComponent(".claude", isDirectory: true) }
}
