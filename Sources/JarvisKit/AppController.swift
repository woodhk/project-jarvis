import AppKit
import AVFoundation
import JarvisCore

/// Builds the parts, hands key events to the coordinator, and owns the menu-bar item.
@MainActor public final class AppController {
    private let pill = PillController()
    private var coordinator: Coordinator?
    private var cards: CardStore?
    private var monitor: KeyMonitor?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var spaceObserver: NSObjectProtocol?
    private var driveObservers: [NSObjectProtocol] = []
    private var transcriber: LazyTranscriber?
    private let setupWindow = SetupWindow()
    private let menuActions = MenuActions()

    public init() {}

    public func start() {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        var config = Config.default
        do {
            config = try Config.load(from: Paths.configFile)
        } catch {
            addMenuNote("The settings file could not be read, so the defaults are in use.")
        }

        let userNames = Scrubber.systemUserNames()
        let runner = AppleScriptRunner()
        let cards = CardStore(configFile: Paths.configFile, claudeDir: Paths.claudeDir, homeDir: Paths.home,
                              inspector: LiveProcessInspector(), catalog: AppCatalog(), userNames: userNames,
                              artifactIndex: ArtifactIndex(claudeDir: Paths.claudeDir, cacheFile: Paths.artifactCache),
                              chromeTabs: { Self.claudeTabs(runner) },
                              debugFile: Paths.appSupport.appendingPathComponent("debug-cards.json"), folderCache: Paths.folderCache)
        self.cards = cards
        cards.refresh()

        let bridge = VSCodeBridge(socketDir: Paths.vscodeSockets)
        let opener = CompositeOpener(terminal: TerminalOpener(runner: runner), vscode: VSCodeOpener(bridge: bridge),
                                     chrome: ChromeOpener(runner: runner), app: AppOpener())
        let trace = TraceHolder()
        let key = KeyHolder()
        let jev = JevClient(key: { key.value }, scrubber: Scrubber(userNames: userNames), timeoutMs: config.thresholds.jevTimeoutMs)
        let remembered = RememberedStore(file: Paths.rememberedFile)
        let picker = Picker(jev: jev, remembered: remembered, thresholds: config.thresholds, trace: { trace.set($0) })
        pill.choiceSeconds = TimeInterval(config.thresholds.choiceTimeoutS)
        pill.listSeconds = TimeInterval(config.thresholds.listTimeoutS)
        let transcriber = LazyTranscriber(modelPath: Paths.modelFile.path)
        self.transcriber = transcriber
        let coordinator = Coordinator(
            recorder: Recorder(), transcriber: transcriber, picker: picker, opener: opener,
            front: FrontReader(runner: runner, bridge: bridge), cards: cards, pill: pill, log: EventLog(file: Paths.logFile),
            thresholds: config.thresholds,
            hintWords: { [words = config.hintWords, weak cards] in
                let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
                let drives = cards?.snapshot.folders.filter { $0.depth == 0 }.map(\.name) ?? []       // "vault", not "fault"
                return words + drives + running + running.compactMap(AppCatalog.shortName)        // "Chrome" as well as "Google Chrome"
            },
            lastTrace: { trace.take() }, remembered: remembered, appControl: LiveAppControl())
        self.coordinator = coordinator
        // A number typed while a list is on show picks that row; any other key closes the list.
        pill.onKey = { [weak coordinator] key in
            Task { @MainActor in await coordinator?.typed(key) }
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak cards] _ in cards?.refresh() }
        // A drive that is plugged in or taken out: list its folders again at once.
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            driveObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak cards] _ in
                cards?.refreshFolders(force: true)
            })
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak coordinator] _ in
                MainActor.assumeIsolated { coordinator?.spaceChanged() }
        }

        let monitor = KeyMonitor(tapThreshold: Double(config.thresholds.tapMs) / 1000) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        self.monitor = monitor
        _ = monitor.start()          // when this fails, the setup window says what to allow

        // The setup window opens by itself only when something Jarvis cannot work without is missing.
        Task { @MainActor [setupWindow] in
            let checks = await SetupProbe().checks()
            if SetupRules.shouldOpenByItself(checks) { setupWindow.show(checks) }
        }
    }

    /// Call when the app is about to quit.
    public func shutDown() {
        transcriber?.unload()
    }

    /// The claude.ai tabs open in Chrome. Called on a background queue; Chrome is never started for it.
    nonisolated private static func claudeTabs(_ runner: AppleScriptRunner) -> [(url: String, title: String)] {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty else { return [] }
        let done = DispatchSemaphore(value: 0)
        let output = TextHolder()
        Task.detached {
            output.set((try? await runner.run(ChromeScripts.claudeTabs)) ?? "")
            done.signal()
        }
        done.wait()
        return ChromeScripts.parseTabs(output.text)
    }

    private func handle(_ event: HoldEvent) {
        if case .began = event { cards?.refresh() }
        guard let coordinator else { return }
        Task { @MainActor in await coordinator.handle(event) }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Jarvis")
        menuActions.setup = { [setupWindow] in setupWindow.show() }
        menuActions.websites = {
            _ = try? Config.load(from: Paths.configFile)          // writes the default file when there is none yet
            NSWorkspace.shared.open(Paths.configFile)
        }
        menuActions.log = {
            let log = Paths.logFile
            let existing = FileManager.default.fileExists(atPath: log.path) ? log : log.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            NSWorkspace.shared.open(existing)
        }
        let menu = NSMenu()
        for (title, action) in [("Setup…", #selector(MenuActions.openSetup)), ("Edit websites…", #selector(MenuActions.editWebsites)),
                                ("Open log", #selector(MenuActions.openLog))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = menuActions
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jarvis", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func addMenuNote(_ text: String) {
        guard let menu = statusItem?.menu else { return }
        let note = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.insertItem(note, at: 0)
        menu.insertItem(.separator(), at: 1)
    }
}

/// The target of the menu items. AppKit needs an object with Objective-C methods for that.
@MainActor private final class MenuActions: NSObject {
    var setup: () -> Void = {}
    var websites: () -> Void = {}
    var log: () -> Void = {}
    @objc func openSetup() { setup() }
    @objc func editWebsites() { websites() }
    @objc func openLog() { log() }
}

private final class TextHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    var text: String { lock.withLock { value } }
    func set(_ new: String) { lock.withLock { value = new } }
}

/// The trace of the pick in progress, handed from the picker to the coordinator's log line.
private final class TraceHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var trace: PickTrace?
    func set(_ new: PickTrace) { lock.withLock { trace = new } }
    func take() -> PickTrace? {
        lock.withLock {
            defer { trace = nil }
            return trace
        }
    }
}

/// Reads the TypeSafe key once it is needed and keeps it in memory, so the Keychain is not asked on every request.
private final class KeyHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    var value: String? {
        lock.withLock {
            if key == nil { key = KeyStore.jevKey() }
            return key
        }
    }
}
