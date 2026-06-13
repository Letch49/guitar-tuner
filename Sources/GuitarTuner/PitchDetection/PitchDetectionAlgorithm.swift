import Foundation

// MARK: - Shared types

/// Constrains pitch detection to an expected frequency range.
/// When the user pins a string, pass its frequency here so the algorithm
/// avoids octave errors and is more sensitive to that string's range.
struct PitchHint {
    let frequency: Double        // target Hz
    let toleranceCents: Double   // search window ±cents

    init(frequency: Double, toleranceCents: Double = 350) {
        self.frequency = frequency
        self.toleranceCents = toleranceCents
    }

    var minFrequency: Double { frequency * pow(2, -toleranceCents / 1200) }
    var maxFrequency: Double { frequency * pow(2,  toleranceCents / 1200) }
}

/// Result returned by any pitch detection algorithm.
struct PitchResult {
    let frequency: Double   // Hz
    let clarity: Double     // 0–1 (higher = more confident)
}

// MARK: - Protocol

/// All pitch-detection algorithms conform to this protocol so that
/// `PitchTracker` can swap them without changing any other code.
protocol PitchDetectionAlgorithm {
    /// Process one window of mono PCM samples.
    /// - Parameters:
    ///   - samples:    Float PCM, normalised to ±1
    ///   - sampleRate: Sample rate in Hz
    ///   - hint:       Optional expected frequency (used when a string is pinned)
    /// - Returns: Best pitch estimate, or nil if the signal is aperiodic / too quiet.
    mutating func process(samples: [Float], sampleRate: Double, hint: PitchHint?) -> PitchResult?

    /// Reset any accumulated state (call after a device switch or silence).
    mutating func reset()
}
