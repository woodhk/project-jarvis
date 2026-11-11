import Foundation

public enum Transcript {
    private static let markers = try! NSRegularExpression(pattern: #"\[[^\]]*\]|\([^)]*\)|\*[^*]*\*"#)

    /// The usable text of a raw transcript, or nil when there is none.
    /// Whisper writes markers such as `[BLANK_AUDIO]` or `(silence)` for sound that is not speech; those are dropped.
    public static func clean(_ raw: String) -> String? {
        let range = NSRange(raw.startIndex..., in: raw)
        let withoutMarkers = markers.stringByReplacingMatches(in: raw, range: range, withTemplate: " ")
        let text = withoutMarkers.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // A spoken number comes back as a digit ("2"), so one digit is enough; otherwise at least two letters.
        let usable = text.contains(where: \.isNumber) || text.filter(\.isLetter).count >= 2
        return usable ? text : nil
    }

    public struct Levels: Equatable, Sendable {
        /// Root mean square of the whole recording.
        public var average: Float
        /// Root mean square of its loudest 0.3 seconds.
        public var loudest: Float
        public var peak: Float
    }

    /// How loud a recording is. Speech has pauses, so the loudest moment says more than the average.
    public static func levels(_ samples: [Float]) -> Levels {
        guard !samples.isEmpty else { return Levels(average: 0, loudest: 0, peak: 0) }
        func rms(_ range: Range<Int>) -> Float {
            var sum: Float = 0
            for index in range { sum += samples[index] * samples[index] }
            return (sum / Float(range.count)).squareRoot()
        }
        let window = 4_800, step = 1_600                       // 0.3 s and 0.1 s at 16 kHz
        var loudest: Float = 0
        if samples.count <= window {
            loudest = rms(0..<samples.count)
        } else {
            var start = 0
            while start + window <= samples.count {
                loudest = max(loudest, rms(start..<start + window))
                start += step
            }
        }
        return Levels(average: rms(0..<samples.count), loudest: loudest, peak: samples.reduce(0) { max($0, abs($1)) })
    }

    /// Below this level in its loudest 0.3 seconds, a recording holds no speech. Quiet microphones (USB earphones)
    /// deliver speech at 0.008 to 0.017, so the line sits well under that.
    public static let silenceLevel: Float = 0.003

    public static func isSilent(_ samples: [Float]) -> Bool {
        levels(samples).loudest < silenceLevel
    }
}
