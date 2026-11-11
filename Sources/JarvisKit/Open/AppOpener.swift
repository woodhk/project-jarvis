import AppKit
import JarvisCore

/// Shows a folder in Finder: its window comes forward if one is open, otherwise a new one opens.
public struct FolderOpener: Opening {
    public init() {}

    public func open(_ destination: Destination) async throws -> String? {
        guard case .folder(let path) = destination else { throw OpenError.failed("Not a folder.") }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else { throw OpenError.gone }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true), configuration: configuration)
        } catch {
            throw OpenError.failed(error.localizedDescription)
        }
        return nil
    }
}

/// Activates an app if it is running, otherwise launches it.
public struct AppOpener: Opening {
    public init() {}

    public func open(_ destination: Destination) async throws -> String? {
        guard case .app(let path) = destination else { throw OpenError.failed("Not an app.") }
        guard FileManager.default.fileExists(atPath: path) else { throw OpenError.gone }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
        } catch {
            throw OpenError.failed(error.localizedDescription)
        }
        return nil
    }
}
