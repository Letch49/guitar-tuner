import Foundation

// PTrack-based pitch detector.
// ZenPTrack is a Swift port of the Csound "ptrack" opcode
// (Victor Lazzarini / Miller Puckette / JP Simard), MIT License.

final class PitchTracker {

    /// Called on the main thread with (detectedFrequencyOrNil, rmsLevel).
    var onResult: ((Double?, Float) -> Void)?

    private var ptrack: ZenPTrack?
    private var currentSampleRate: Double = 0

    // 0.01 ≈ -40 dB. Noise at this level is filtered by the consistency
    // check in TunerViewModel (~360 ms of stable signal required).
    private let amplitudeThreshold: Double = 0.01

    /// Pre-gain applied before PTrack. Increase for lower tunings to compensate
    /// for the reduced acoustic output of low strings through a mic.
    var gain: Float = 3.0

    func reset() {
        if currentSampleRate > 0 {
            ptrack = ZenPTrack(sampleRate: currentSampleRate, hopSize: 4096, peakCount: 20)
        }
    }

    func append(_ samples: [Float], sampleRate: Double) {
        if sampleRate != currentSampleRate || ptrack == nil {
            currentSampleRate = sampleRate
            ptrack = ZenPTrack(sampleRate: sampleRate, hopSize: 4096, peakCount: 20)
        }

        guard var pt = ptrack else { return }

        // RMS for level meter
        var rmsSum: Float = 0
        for s in samples { rmsSum += s * s }
        let rms = sqrtf(rmsSum / Float(max(1, samples.count)))

        let gain = self.gain

        var pitch = 0.0
        var amplitude = 0.0
        for sample in samples {
            pt.compute(bufferValue: sample * gain, pitch: &pitch, amplitude: &amplitude)
        }

        ptrack = pt

        let detected: Double? = (amplitude > amplitudeThreshold && pitch > 0) ? pitch : nil
        DispatchQueue.main.async { [weak self] in
            self?.onResult?(detected, rms)
        }
    }
}
