import Foundation
import Testing
@testable import JarvisCore
@testable import JarvisKit

enum Fixture {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    /// Reads a 16-bit mono WAV file into samples between -1 and 1.
    static func samples(_ name: String) throws -> [Float] {
        let data = try Data(contentsOf: dir.appendingPathComponent("\(name).wav"))
        var offset = 12
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = Int(data[offset + 4]) | Int(data[offset + 5]) << 8 | Int(data[offset + 6]) << 16 | Int(data[offset + 7]) << 24
            let start = offset + 8
            if id == "data" {
                let end = min(start + size, data.count)
                return stride(from: start, to: end - 1, by: 2).map { i in
                    Float(Int16(bitPattern: UInt16(data[i]) | UInt16(data[i + 1]) << 8)) / 32768
                }
            }
            offset = start + size + (size % 2)
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}

func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-kit-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let real = realpath(dir.path, nil) else { return dir }
    defer { free(real) }
    return URL(fileURLWithPath: String(cString: real), isDirectory: true)
}

/// A value shared between the test and code that runs off the main thread.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: Value) { lock.lock(); value = new; lock.unlock() }
    func update(_ change: (inout Value) -> Void) { lock.lock(); change(&value); lock.unlock() }
}

final class FakeRecorder: Recording {
    /// One second of a 440 Hz tone: loud enough not to count as silence.
    static let tone: [Float] = (0..<16_000).map { 0.1 * sin(Float($0) * 2 * .pi * 440 / 16_000) }
    var samples: [Float] = FakeRecorder.tone
    var starts = 0, stops = 0
    func start() throws { starts += 1 }
    func stop() -> [Float] { stops += 1; return samples }
}

final class FakeTranscriber: Transcribing, @unchecked Sendable {
    private let state: Locked<(next: String, calls: Int, lastHint: String)>
    init(_ text: String) { state = Locked((text, 0, "")) }
    var next: String { get { state.get().next } set { state.update { $0.next = newValue } } }
    var calls: Int { state.get().calls }
    var lastHint: String { state.get().lastHint }
    func transcribe(_ samples: [Float], hint: String) -> String {
        state.update { $0.calls += 1; $0.lastHint = hint }
        return state.get().next
    }
}

/// Counts calls. Understands "back" and, while choices show, "one" and "two", as the real picker does.
/// Otherwise it answers with `outcome` when one is scripted, and through `NameOnlyPicker` when none is.
final class FakePicker: Picking, @unchecked Sendable {
    private let state: Locked<(outcome: Outcome?, calls: Int, prepareCalls: Int, contexts: [PickContext])>
    private let heardBox = Locked<[String]>([])
    /// Every transcript the picker was asked about, in order.
    var transcripts: [String] { heardBox.get() }
    init(outcome: Outcome? = nil) { state = Locked((outcome, 0, 0, [])) }
    var outcome: Outcome? { get { state.get().outcome } set { state.update { $0.outcome = newValue } } }
    var calls: Int { state.get().calls }
    var prepareCalls: Int { state.get().prepareCalls }
    var contexts: [PickContext] { state.get().contexts }
    func prepare() { state.update { $0.prepareCalls += 1 } }
    func pick(transcript: String, cards: CardSnapshot, context: PickContext) async -> Outcome {
        state.update { $0.calls += 1; $0.contexts.append(context) }
        heardBox.update { $0.append(transcript) }
        let words = Normalizer.words(transcript)
        if words == ["back"] { return .back }
        if context.choosing, let index = Picker.choiceIndex(words) { return .pickChoice(index) }
        if context.choosing, Picker.saysYes(words) { return .pickChoice(0) }
        if context.choosing, Picker.saysNo(words) { return .cancel }
        if let scripted = state.get().outcome { return scripted }
        return await NameOnlyPicker().pick(transcript: transcript, cards: cards, context: context)
    }
}

final class FakeOpener: Opening, @unchecked Sendable {
    private let state = Locked<(opened: [Destination], error: OpenError?, note: String?)>(([], nil, nil))
    var opened: [Destination] { state.get().opened }
    var error: OpenError? { get { state.get().error } set { state.update { $0.error = newValue } } }
    var note: String? { get { state.get().note } set { state.update { $0.note = newValue } } }
    func open(_ destination: Destination) async throws -> String? {
        if let error = state.get().error { throw error }
        state.update { $0.opened.append(destination) }
        return state.get().note
    }
}

/// Running apps that can be hidden and quit, without touching a real one.
final class FakeAppControl: AppControlling, @unchecked Sendable {
    private let state = Locked<(running: Set<String>, hidden: [String], quit: [String], hideResult: AppControlResult, quitResult: AppControlResult)>(
        ([], [], [], .done, .done))
    var running: Set<String> { get { state.get().running } set { state.update { $0.running = newValue } } }
    var hidden: [String] { state.get().hidden }
    var quit: [String] { state.get().quit }
    private let frontBox = Locked<(name: String, path: String)?>(nil)
    var front: (name: String, path: String)? { get { frontBox.get() } set { frontBox.set(newValue) } }
    func frontApp() -> (name: String, path: String)? { frontBox.get() }
    var hideResult: AppControlResult { get { state.get().hideResult } set { state.update { $0.hideResult = newValue } } }
    var quitResult: AppControlResult { get { state.get().quitResult } set { state.update { $0.quitResult = newValue } } }
    func isRunning(path: String) -> Bool { state.get().running.contains(path) }
    func hide(path: String) async -> AppControlResult {
        state.update { $0.hidden.append(path) }
        return state.get().hideResult
    }
    func quit(path: String) async -> AppControlResult {
        state.update { $0.quit.append(path) }
        return state.get().quitResult
    }
}

final class FakeFront: FrontReading, @unchecked Sendable {
    private let box = Locked(FrontState(card: .none, destination: nil))
    var state: FrontState { get { box.get() } set { box.set(newValue) } }
    func read(cards: CardSnapshot) async -> FrontState { box.get() }
}

final class FakeCards: CardProviding {
    var snapshot: CardSnapshot
    var refreshes = 0
    init(_ snapshot: CardSnapshot) { self.snapshot = snapshot }
    func refresh() { refreshes += 1 }
}

@MainActor final class FakePill: PillShowing {
    var states: [PillState] = []
    var last: PillState? { states.last }
    func show(_ state: PillState) { states.append(state) }
}

/// Time that only moves when the test says so.
@MainActor final class FakeScheduler: Scheduling {
    private var now: TimeInterval = 0
    private var waiting: [(due: TimeInterval, work: @MainActor () -> Void)] = []
    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        waiting.append((now + seconds, work))
    }
    func advance(by seconds: TimeInterval) {
        now += seconds
        let due = waiting.filter { $0.due <= now }
        waiting.removeAll { $0.due <= now }
        due.forEach { $0.work() }
    }
}

struct FakeRunner: ScriptRunning {
    var result: String
    func run(_ source: String) async throws -> String { result }
}

/// A coordinator wired to fakes.
@MainActor final class Kit {
    static let defaultCards = CardSnapshot(apps: [AppCard(name: "ChatGPT", aliases: [], path: "/Applications/ChatGPT.app")],
                                           sites: Config.default.sites)
    let recorder = FakeRecorder()
    let transcriber: FakeTranscriber
    let picker: FakePicker
    let opener = FakeOpener()
    let front = FakeFront()
    let apps = FakeAppControl()
    let cards: FakeCards
    let pill = FakePill()
    let scheduler = FakeScheduler()
    let logFile: URL
    let remembered = RememberedStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-kit-remembered-\(UUID().uuidString).json"))
    private let traceBox = Locked<PickTrace?>(nil)
    var trace: PickTrace? { get { traceBox.get() } set { traceBox.set(newValue) } }
    private(set) var coordinator: Coordinator!

    init(heard: String, cards: CardSnapshot? = nil, outcome: Outcome? = nil, hintWords: [String] = []) {
        transcriber = FakeTranscriber(heard)
        picker = FakePicker(outcome: outcome)
        self.cards = FakeCards(cards ?? Kit.defaultCards)
        logFile = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-kit-log-\(UUID().uuidString).jsonl")
        coordinator = Coordinator(recorder: recorder, transcriber: transcriber, picker: picker, opener: opener, front: front,
                                  cards: self.cards, pill: pill, log: EventLog(file: logFile), thresholds: Thresholds(),
                                  scheduler: scheduler, hintWords: { hintWords }, lastTrace: { [traceBox] in traceBox.get() },
                                  remembered: remembered, appControl: apps)
    }

    /// A normal request: the key goes down, then up one second later.
    func hold(for seconds: TimeInterval = 1) async {
        await coordinator.handle(.began)
        await coordinator.handle(.ended(duration: seconds))
    }

    var logged: [EventRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let text = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { try? decoder.decode(EventRecord.self, from: Data($0.utf8)) }
    }
}

/// True when `osacompile` accepts the script. It only checks the script; it does not run it.
func compiles(_ script: String) throws -> Bool {
    let dir = try tempDir()
    let source = dir.appendingPathComponent("script.applescript")
    try script.write(to: source, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
    process.arguments = ["-o", dir.appendingPathComponent("out.scpt").path, source.path]
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        print(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
    return process.terminationStatus == 0
}
