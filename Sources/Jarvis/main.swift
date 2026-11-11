import AppKit
import JarvisCore
import JarvisKit

// `Jarvis --list-sessions` prints the open Claude Code sessions as Jarvis sees them, and exits without starting the app.
if CommandLine.arguments.contains("--list-sessions") {
    let began = Date()
    let reader = SessionReader(claudeDir: Paths.claudeDir, homeDir: Paths.home, inspector: LiveProcessInspector())
    let sessions = reader.openSessions()
    let ms = Int(Date().timeIntervalSince(began) * 1000)
    let gistsBegan = Date()
    let gists = GistBuilder(userNames: Scrubber.systemUserNames())
        .gists(historyFile: Paths.claudeDir.appendingPathComponent("history.jsonl"), for: Set(sessions.map(\.id)))
    let gistMs = Int(Date().timeIntervalSince(gistsBegan) * 1000)
    let repliesBegan = Date()
    var files: [String: URL] = [:]
    for s in sessions { files[s.id] = reader.historyFile(for: s.id) }
    let replyBuilder = ReplyGistBuilder(userNames: Scrubber.systemUserNames())
    let replies = replyBuilder.gists(historyFiles: files)
    let replyMs = Int(Date().timeIntervalSince(repliesBegan) * 1000)
    let againBegan = Date()
    _ = replyBuilder.gists(historyFiles: files)
    let againMs = Int(Date().timeIntervalSince(againBegan) * 1000)
    for s in sessions {
        print("\(s.pid)\t\(s.host.rawValue)\t\(s.tty)\t\(s.folderLabel)\t\(s.label)\t\((gists[s.id] ?? []).joined(separator: ", "))\t\((replies[s.id] ?? []).joined(separator: ", "))")
    }
    FileHandle.standardError.write(Data("\(sessions.count) sessions read in \(ms) ms; gists built in \(gistMs) ms; reply words from \(replyBuilder.bytesRead / 1_000_000) MB of history in \(replyMs) ms (again, nothing new: \(againMs) ms)\n".utf8))
    exit(0)
}

// `Jarvis --list-artifacts` times a first and a second scan for artifacts (with a throwaway cache) and prints counts only.
if CommandLine.arguments.contains("--list-artifacts") {
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-artifact-timing-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cache) }
    let index = ArtifactIndex(claudeDir: Paths.claudeDir, cacheFile: cache)
    let firstBegan = Date()
    let cards = index.refresh()
    let firstMs = Int(Date().timeIntervalSince(firstBegan) * 1000)
    let secondBegan = Date()
    _ = index.refresh()
    let secondMs = Int(Date().timeIntervalSince(secondBegan) * 1000)
    let open = Set(SessionReader(claudeDir: Paths.claudeDir, homeDir: Paths.home, inspector: LiveProcessInspector()).openSessions().map(\.id))
    let linked = cards.filter { card in card.links.contains { open.contains($0.sessionId) } }
    print("\(cards.count) artifacts in the last 30 days; \(cards.filter { $0.title != nil }.count) with a title, "
        + "\(cards.filter { $0.description != nil }.count) with a description; \(linked.count) linked to an open session")
    print("first scan \(firstMs) ms; second scan \(secondMs) ms")
    exit(0)
}

// `Jarvis --check-setup` prints the setup checks. Run from a terminal, the three permission lines describe that
// terminal, not the Jarvis app; the setup window inside the app is the true picture for those.
if CommandLine.arguments.contains("--check-setup") {
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        for check in await SetupProbe().checks() {
            switch check.status {
            case .ok: print("ok      \(check.id)")
            case .needsAction(let action): print("TO DO   \(check.id): \(action)")
            }
        }
        done.signal()
    }
    done.wait()
    exit(0)
}

// `Jarvis --render-pill <folder>` writes a picture of each pill state into the folder. Nothing appears on screen.
if let flag = CommandLine.arguments.firstIndex(of: "--render-pill"), CommandLine.arguments.count > flag + 1 {
    let folder = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    MainActor.assumeIsolated {
        let states: [(String, PillState)] = [
            ("1-listening", .listening),
            ("2-hint", .hint(PillCopy.keepHolding)),
            ("3-working", .working(heard: "Open the open source insta to comment session.")),
            ("4-opened", .opened(heard: "Open the open source insta to comment session.", title: "Shareable repo setup guide",
                                 subtitle: "VS Code · insta-comment-dm", note: PillCopy.backTip)),
            ("5-choices", .choices(heard: "Open the insta session.", options: [
                PillOption(title: "IDEAS2 Instagram reel tracking", subtitle: "VS Code · insta-comment-dm"),
                PillOption(title: "Shareable repo setup guide", subtitle: "VS Code · insta-comment-dm")])),
            ("6-nothing", .nothing(heard: "Open the session about my tax return.", message: PillCopy.nothingMatches)),
            ("8-list", .list(options: [
                PillOption(title: "pattern-reel", subtitle: "Terminal · stream_audio_converter · just now"),
                PillOption(title: "IDEAS2 Instagram reel tracking", subtitle: "VS Code · insta-comment-dm · 5 min ago"),
                PillOption(title: "Shareable repo setup guide", subtitle: "VS Code · insta-comment-dm · 40 min ago"),
                PillOption(title: "discovery-reel", subtitle: "Terminal · stream_audio_converter · 2 h ago"),
                PillOption(title: "Emotion-tagged GIF library", subtitle: "VS Code · stream_audio_converter · 3 h ago"),
                PillOption(title: "Chip design software", subtitle: "VS Code · gadget-lab · 1 d ago")], more: 0, listening: false)),
            ("10-question", .choices(heard: "Quit Terminal.", options: [
                PillOption(title: PillCopy.quitQuestion("Terminal"), subtitle: PillCopy.endsSessions(3))])),
            ("11-hidden", .opened(heard: "Can you close Spotify?", title: "Spotify", subtitle: PillCopy.hidden, note: PillCopy.hiddenNote("Spotify"))),
            ("9-list-listening", .list(options: [
                PillOption(title: "pattern-reel", subtitle: "Terminal · stream_audio_converter · just now"),
                PillOption(title: "IDEAS2 Instagram reel tracking", subtitle: "VS Code · insta-comment-dm · 5 min ago")], more: 4, listening: true)),
            ("7-unheard", .nothing(heard: "", message: PillCopy.didNotCatch)),
        ]
        for (name, state) in states {
            try? PillController.renderPNG(state)?.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
    exit(0)
}

// `Jarvis --transcribe <file.wav> ...` prints what the speech model writes for each 16 kHz mono 16-bit WAV file, raw,
// using the same word hints as the app. For finding out why something was not understood.
if let flag = CommandLine.arguments.firstIndex(of: "--transcribe"), CommandLine.arguments.count > flag + 1 {
    let reader = SessionReader(claudeDir: Paths.claudeDir, homeDir: Paths.home, inspector: LiveProcessInspector())
    let config = (try? Config.load(from: Paths.configFile)) ?? .default
    let hint = CardSnapshot(sessions: reader.openSessions(), sites: config.sites).vocabularyHint(extraWords: config.hintWords)
    // The model is freed (the closure ends) before the program does; see LazyTranscriber.unload().
    let ok: Bool = {
        guard let transcriber = try? Transcriber(modelPath: Paths.modelFile.path) else { return false }
        for path in CommandLine.arguments[(flag + 1)...] {
            guard let data = FileManager.default.contents(atPath: path), data.count > 44 else { continue }
            let samples = stride(from: 44, to: data.count - 1, by: 2).map { Float(Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8)) / 32768 }
            let raw = transcriber.transcribe(samples, hint: hint)
            print("\(URL(fileURLWithPath: path).lastPathComponent): raw \(raw.debugDescription) -> cleaned \(Transcript.clean(raw).debugDescription)")
        }
        return true
    }()
    if !ok { FileHandle.standardError.write(Data("The speech model is missing.\n".utf8)) }
    exit(ok ? 0 : 1)
}

// `Jarvis --pick "<phrase>" ...` shows what Jarvis would do with each phrase right now, and what Jev answered. It asks
// Jev exactly as the app does, and opens nothing. Remembered choices are left out, so the answer is always worked out.
// The Chrome tab titles are taken from the running app's last look (this program does not talk to Chrome).
if let flag = CommandLine.arguments.firstIndex(of: "--pick"), CommandLine.arguments.count > flag + 1 {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-pick-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let cache = scratch.appendingPathComponent("artifact-index.json")
    try? FileManager.default.copyItem(at: Paths.artifactCache, to: cache)
    let seenTabs: [(url: String, title: String)] = {
        guard let data = try? Data(contentsOf: Paths.appSupport.appendingPathComponent("debug-cards.json")),
              let dump = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return (dump["tabs"] as? [[String: String]] ?? []).compactMap { tab in
            guard let url = tab["url"], let title = tab["title"] else { return nil }
            return (url, title)
        }
    }()
    let config = (try? Config.load(from: Paths.configFile)) ?? .default
    let userNames = Scrubber.systemUserNames()
    let store = CardStore(configFile: Paths.configFile, claudeDir: Paths.claudeDir, homeDir: Paths.home, inspector: LiveProcessInspector(),
                          catalog: AppCatalog(), userNames: userNames,
                          artifactIndex: ArtifactIndex(claudeDir: Paths.claudeDir, cacheFile: cache), chromeTabs: { seenTabs },
                          folderCache: scratch.appendingPathComponent("folder-index.json"))
    let foldersBegan = Date()
    store.loadNow()
    FileHandle.standardError.write(Data("cards loaded in \(Int(Date().timeIntervalSince(foldersBegan) * 1000)) ms, \(store.snapshot.folders.count) folders\n".utf8))
    let cards = store.snapshot
    final class Last: @unchecked Sendable { var trace: PickTrace? }
    let last = Last()
    var thresholds = config.thresholds
    thresholds.jevTimeoutMs = 5000          // the answer is wanted here, however long it takes; the time is printed
    let picker = Picker(jev: JevClient(key: { KeyStore.jevKey() }, scrubber: Scrubber(userNames: userNames), timeoutMs: thresholds.jevTimeoutMs),
                        remembered: RememberedStore(file: scratch.appendingPathComponent("remembered.json")),
                        thresholds: thresholds, trace: { last.trace = $0 })
    print("\(cards.sessions.count) sessions, \(cards.artifacts.count) pages, \(seenTabs.count) Chrome tab titles")
    let done = DispatchSemaphore(value: 0)
    let phrases = Array(CommandLine.arguments[(flag + 1)...])
    Task.detached {
        for phrase in phrases {
            let began = Date()
            let outcome = await picker.pick(transcript: phrase, cards: cards, context: PickContext(front: .none, choosing: false))
            let ms = Int(Date().timeIntervalSince(began) * 1000)
            let result: String
            switch outcome {
            case .open(let target): result = "OPEN  \(target.title)  (\(target.subtitle))"
            case .choices(let targets, _): result = "LIST  " + targets.map { "\($0.title) (\($0.subtitle))" }.joined(separator: "  |  ")
            case .list(let targets): result = "ALL   " + targets.enumerated().map { "\($0.offset + 1) \($0.element.title)" }.joined(separator: "  |  ")
            case .app(let wanted):
                let ask = wanted.ask.map { " (asks first: \($0))" } ?? ""
                result = "\(wanted.action == .hide ? "CLOSE (hide)" : "QUIT")  \(wanted.target.title)\(ask), if it is running"
            case .appInFront(let action): result = "\(action == .hide ? "CLOSE (hide)" : "QUIT, after a yes:") the app in front"
            case .appUnknown: result = "NO APP NAMED: nothing is closed"
            case .nothing: result = "NOTHING"
            case .back: result = "BACK"
            case .pickChoice(let index): result = "CHOICE \(index + 1)"
            case .cancel: result = "CANCEL"
            case .unknownName: result = "UNKNOWN NAME: nothing opens"
            }
            print("\n\"\(phrase)\"  ->  \(result)   [\(last.trace?.step ?? "?"), \(ms) ms]")
            for (question, options) in (last.trace?.answers ?? [:]).sorted(by: { $0.key < $1.key }) {
                let line = options.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.filter { $0.value >= 0.01 }
                    .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                print("    \(question): \(line)")
            }
        }
        done.signal()
    }
    done.wait()
    exit(0)
}

// `Jarvis --app hide|quit "<App name>"` does to a running app what "close <name>" or "quit <name>" does, and prints the
// result. For checking that hiding and quitting work on this Mac.
if let flag = CommandLine.arguments.firstIndex(of: "--app"), CommandLine.arguments.count > flag + 2 {
    let (verb, name) = (CommandLine.arguments[flag + 1], CommandLine.arguments[flag + 2])
    guard let card = AppCatalog().apps(aliases: [:]).first(where: { Normalizer.compact($0.name) == Normalizer.compact(name) }),
          verb == "hide" || verb == "quit" else {
        FileHandle.standardError.write(Data("Usage: Jarvis --app hide|quit \"<name of an installed app>\"\n".utf8))
        exit(2)
    }
    final class Box: @unchecked Sendable { var result: AppControlResult? }
    let box = Box()
    Task.detached {
        let control = LiveAppControl()
        box.result = verb == "hide" ? await control.hide(path: card.path) : await control.quit(path: card.path)
    }
    // The main run loop keeps turning while this waits, as it does in the app: what is known about other apps
    // (hidden, gone) only updates there.
    while box.result == nil { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    print("\(verb) \(card.name): \(box.result!)")
    exit(box.result == .done ? 0 : 1)
}

// `Jarvis --check-keys` says whether macOS lets the pill take the keyboard (for typing a number into a list) while
// another app stays in front. Nothing is shown; it takes a fraction of a second.
if CommandLine.arguments.contains("--check-keys") {
    let ok = MainActor.assumeIsolated { () -> Bool in
        NSApplication.shared.setActivationPolicy(.accessory)
        return PillController.canTakeKeys()
    }
    print(ok ? "ok: the pill can take the keyboard without coming to the front" : "NO: the pill did not get the keyboard")
    exit(ok ? 0 : 1)
}

// `Jarvis --store-key` copies TYPESAFE_API_KEY from the shell into the login Keychain. The key is never printed.
if CommandLine.arguments.contains("--store-key") {
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
        FileHandle.standardError.write(Data("TYPESAFE_API_KEY is not set in this shell. Nothing was stored.\n".utf8))
        exit(1)
    }
    if KeyStore.store(key) {
        print("Stored the TypeSafe key in your login Keychain (service \"Jarvis\").")
        exit(0)
    }
    FileHandle.standardError.write(Data("The Keychain refused to store the key.\n".utf8))
    exit(1)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController()
        self.controller = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutDown()
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
