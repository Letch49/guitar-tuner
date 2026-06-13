import Foundation

/// Wraps ZenPTrack (sample-by-sample FFT-based tracker) in the unified
/// PitchDetectionAlgorithm protocol. ZenPTrack is stateful and must be
/// re-created when the sample rate changes.
struct PTrackDetector: PitchDetectionAlgorithm {

    private var tracker: ZenPTrack?
    private var lastSampleRate: Double = 0

    mutating func reset() {
        tracker = nil
        lastSampleRate = 0
    }

    mutating func process(samples: [Float],
                          sampleRate: Double,
                          hint: PitchHint?) -> PitchResult? {
        if tracker == nil || sampleRate != lastSampleRate {
            lastSampleRate = sampleRate
            // hopSize must be a power of two; 512 gives ~11.6 ms frames.
            tracker = ZenPTrack(sampleRate: sampleRate, hopSize: 512, peakCount: 20)
        }

        var pitch: Double = 0
        var amplitude: Double = 0
        for sample in samples {
            tracker!.compute(bufferValue: sample, pitch: &pitch, amplitude: &amplitude)
        }

        guard pitch.isFinite, pitch > 20 else { return nil }

        // Clamp to hint window when available (same as MPM/YIN)
        if let hint {
            guard pitch >= hint.minFrequency, pitch <= hint.maxFrequency else { return nil }
        }

        return PitchResult(frequency: pitch, clarity: min(1.0, amplitude * 0.5))
    }
}
