import Foundation
import Testing
@testable import JarvisCore

@Test func markersAndSilenceCleanToNil() {
    for junk in ["", "   ", "[BLANK_AUDIO]", " (silence) ", "[ Silence ]", ".", "*music*"] {
        #expect(Transcript.clean(junk) == nil)
    }
    #expect(Transcript.clean("  Open YouTube.\n") == "Open YouTube.")
}

@Test func aMarkerBesideSpeechIsDropped() {
    #expect(Transcript.clean("[BLANK_AUDIO] open YouTube") == "open YouTube")
}

@Test func quietRecordingsCountAsSilence() {
    #expect(Transcript.isSilent([Float](repeating: 0, count: 16000)))
    #expect(Transcript.isSilent([]))
    #expect(!Transcript.isSilent((0..<16000).map { 0.1 * sin(Float($0) * 2 * .pi * 440 / 16000) }))
}

@Test func theLogWritesOneJSONObjectPerLine() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-log-\(UUID().uuidString)/events.jsonl")
    let log = EventLog(file: file)
    let first = EventRecord(at: Date(timeIntervalSince1970: 1_800_000_000), heard: "open YouTube", outcome: "opened",
                            title: "YouTube", ms: ["transcribe": 160, "total": 480], step: "name", top: nil)
    log.write(first)
    log.write(EventRecord(at: Date(timeIntervalSince1970: 1_800_000_005), heard: "", outcome: "unheard", title: nil, ms: [:], step: nil, top: nil))
    let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(EventRecord.self, from: Data(lines[0].utf8)) == first)
}

// From the first hand test: two clips of about seven seconds were judged silent and never transcribed.
// Speech with pauses, or from a quiet microphone, has a low average level; its loudest moment is what counts.
@Test func aLongClipWithShortSpeechIsNotSilence() {
    var clip = [Float](repeating: 0.0005, count: 7 * 16_000)
    for i in 0..<8_000 { clip[40_000 + i] = 0.02 * sin(Float(i) * 2 * .pi * 300 / 16_000) }     // half a second of quiet speech
    #expect(!Transcript.isSilent(clip))
    #expect(Transcript.isSilent([Float](repeating: 0.001, count: 7 * 16_000)))                 // a steady hum is still silence
    let levels = Transcript.levels(clip)
    #expect(levels.loudest > levels.average * 2)
    #expect(abs(levels.peak - 0.02) < 0.001)
    #expect(Transcript.levels([]) == Transcript.Levels(average: 0, loudest: 0, peak: 0))
}

// From the second hand test: saying "two" to pick the second choice did nothing. The speech model writes "2",
// and a transcript with fewer than two letters was thrown away.
@Test func aSpokenNumberIsATranscript() {
    #expect(Transcript.clean(" 2") == "2")
    #expect(Transcript.clean(" 1.") == "1.")
    #expect(Transcript.clean("a") == nil)
    #expect(Transcript.clean(" . ") == nil)
}

// The user's USB earphone microphone is quiet: speech peaked at 0.008 to 0.017 in its loudest 0.3 seconds.
@Test func quietSpeechFromAQuietMicrophoneIsNotSilence() {
    func tone(_ amplitude: Float) -> [Float] { (0..<16_000).map { amplitude * sin(Float($0) * 2 * .pi * 300 / 16_000) } }
    #expect(!Transcript.isSilent(tone(0.006)))        // level about 0.0042
    #expect(Transcript.isSilent(tone(0.003)))         // level about 0.0021
}
