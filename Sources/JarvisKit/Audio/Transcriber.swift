import CGGML
import CWhisper
import Foundation

public protocol Transcribing: Sendable {
    /// Samples are 16 kHz mono. `hint` is a list of words the speaker is likely to say.
    func transcribe(_ samples: [Float], hint: String) -> String
}

public enum TranscriberError: Error, Equatable {
    case cannotLoadModel(String)
}

/// Speech to text on this Mac, through whisper.cpp. The model is loaded once; calls run one at a time.
public final class Transcriber: Transcribing, @unchecked Sendable {
    private let context: OpaquePointer
    private let lock = NSLock()
    /// whisper.cpp does not accept less than one second of audio, so short clips are padded with silence to this length.
    private static let minimumSamples = 17_600

    /// Homebrew builds ggml with its compute backends (Metal, CPU) as plug-ins. They must be loaded once before a model is.
    private static let backendsLoaded: Void = {
        whisper_log_set({ _, _, _ in }, nil)   // keep the library quiet on stderr
        ggml_backend_load_all()
    }()

    public init(modelPath: String) throws {
        _ = Self.backendsLoaded
        guard FileManager.default.fileExists(atPath: modelPath) else { throw TranscriberError.cannotLoadModel(modelPath) }
        var parameters = whisper_context_default_params()
        parameters.use_gpu = true
        guard let context = whisper_init_from_file_with_params(modelPath, parameters) else {
            throw TranscriberError.cannotLoadModel(modelPath)
        }
        self.context = context
    }

    deinit { whisper_free(context) }

    public func transcribe(_ samples: [Float], hint: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        var audio = samples
        if audio.count < Self.minimumSamples {
            audio.append(contentsOf: [Float](repeating: 0, count: Self.minimumSamples - audio.count))
        }
        var parameters = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        parameters.beam_search.beam_size = 5
        parameters.no_timestamps = true
        parameters.single_segment = true
        parameters.no_context = true
        parameters.print_special = false
        parameters.print_progress = false
        parameters.print_realtime = false
        parameters.print_timestamps = false
        return "en".withCString { language in
            hint.withCString { prompt in
                parameters.language = language
                parameters.initial_prompt = hint.isEmpty ? nil : prompt
                let status = audio.withUnsafeBufferPointer { whisper_full(context, parameters, $0.baseAddress, Int32($0.count)) }
                guard status == 0 else { return "" }
                var text = ""
                for index in 0..<whisper_full_n_segments(context) {
                    if let segment = whisper_full_get_segment_text(context, index) { text += String(cString: segment) }
                }
                return text
            }
        }
    }
}

/// Loads the model in the background at start-up and runs it once on silence, so the first real request is not slow.
/// A request that arrives before loading has finished waits for it. With no model, every transcript is empty.
public final class LazyTranscriber: Transcribing, @unchecked Sendable {
    private let loading = DispatchGroup()
    private var loaded: Transcriber?

    public init(modelPath: String) {
        loading.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            loaded = try? Transcriber(modelPath: modelPath)
            _ = loaded?.transcribe([], hint: "")
            loading.leave()
        }
    }

    /// True once the model is loaded. False while loading, and for good when the model file is missing or unreadable.
    public var isReady: Bool {
        loading.wait(timeout: .now()) == .success && loaded != nil
    }

    public func transcribe(_ samples: [Float], hint: String) -> String {
        loading.wait()
        return loaded?.transcribe(samples, hint: hint) ?? ""
    }

    /// Frees the model. Call before the program ends: the speech library stops the program at exit
    /// (a crash report) when a model is still loaded.
    public func unload() {
        loading.wait()
        loaded = nil
    }
}
