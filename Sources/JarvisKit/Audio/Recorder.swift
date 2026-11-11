import AVFoundation

public protocol Recording: AnyObject {
    func start() throws
    /// Stops and returns what was recorded since `start()`, as 16 kHz mono samples.
    func stop() -> [Float]
}

public enum RecorderError: Error, Equatable {
    case notAllowed
    case noInputDevice
}

/// Records from the default microphone between `start()` and `stop()`. Audio stays in memory and is never written to disk.
///
/// Every hold gets a new audio engine. An engine that outlives a change of audio hardware (headphones connected,
/// another microphone chosen) can deliver nothing, or stop the app, and macOS does not always report the change to
/// an engine that is not running.
public final class Recorder: Recording {
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var engine: AVAudioEngine?

    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var converterSource: AVAudioFormat?

    public init() {}

    public func start() throws {
        guard engine == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw RecorderError.notAllowed }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard input.outputFormat(forBus: 0).sampleRate > 0 else { throw RecorderError.noInputDevice }
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        converter = nil
        converterSource = nil
        lock.unlock()
        // `format: nil` takes whatever the hardware delivers now; each buffer is converted from its own format.
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            self.engine = engine
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    public func stop() -> [Float] {
        guard let engine else { return [] }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        lock.lock()
        defer { lock.unlock() }
        let recorded = samples
        samples.removeAll(keepingCapacity: true)
        return recorded
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        if converter == nil || converterSource != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converterSource = buffer.format
        }
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var handedOver = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if handedOver {
                status.pointee = .noDataNow
                return nil
            }
            handedOver = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData, output.frameLength > 0 else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }
}
