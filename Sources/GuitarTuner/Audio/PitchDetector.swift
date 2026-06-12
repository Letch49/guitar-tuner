import Foundation
import Accelerate

/// Monophonic pitch detection using the YIN algorithm
/// (de Cheveigné & Kawahara, 2002) with parabolic interpolation.
enum YIN {
    /// - Returns: detected fundamental frequency in Hz, or nil if no clear pitch.
    static func detectPitch(
        in samples: [Float],
        sampleRate: Double,
        minFrequency: Double = 52,   // just below A1 (55 Hz), above 50 Hz mains hum
        maxFrequency: Double = 600,  // highest open string E4 = 330 Hz, with margin
        threshold: Float = 0.2
    ) -> Double? {
        let n = samples.count
        let tauMin = max(2, Int(sampleRate / maxFrequency))
        let tauMax = min(n / 2, Int(sampleRate / minFrequency))
        guard tauMax > tauMin + 2 else { return nil }

        let windowLength = n - tauMax

        // Difference function: d[tau] = sum_{i} (x[i] - x[i+tau])^2
        var d = [Float](repeating: 0, count: tauMax + 1)
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for tau in 1...tauMax {
                var dist: Float = 0
                vDSP_distancesq(base, 1, base + tau, 1, &dist, vDSP_Length(windowLength))
                d[tau] = dist
            }
        }

        // Cumulative mean normalized difference function.
        var cmnd = [Float](repeating: 1, count: tauMax + 1)
        var runningSum: Float = 0
        for tau in 1...tauMax {
            runningSum += d[tau]
            cmnd[tau] = runningSum > 0 ? d[tau] * Float(tau) / runningSum : 1
        }

        // Absolute threshold: first tau where cmnd dips below threshold,
        // then descend to the local minimum.
        var tauEstimate = -1
        var tau = tauMin
        while tau <= tauMax {
            if cmnd[tau] < threshold {
                while tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau] {
                    tau += 1
                }
                tauEstimate = tau
                break
            }
            tau += 1
        }

        // Fallback for weak fundamentals (e.g. low strings through a laptop mic):
        // accept the global minimum, but only if it is still a clear dip —
        // anything weaker is noise and produces phantom notes.
        if tauEstimate < 0 {
            var bestTau = tauMin
            var bestValue = cmnd[tauMin]
            for tau in tauMin...tauMax where cmnd[tau] < bestValue {
                bestValue = cmnd[tau]
                bestTau = tau
            }
            if bestValue < 0.42 {
                tauEstimate = bestTau
            }
        }
        guard tauEstimate > 0 else { return nil }

        // Parabolic interpolation around the minimum for sub-sample precision.
        let betterTau: Double
        if tauEstimate > tauMin && tauEstimate < tauMax {
            let s0 = Double(cmnd[tauEstimate - 1])
            let s1 = Double(cmnd[tauEstimate])
            let s2 = Double(cmnd[tauEstimate + 1])
            let denominator = 2 * (2 * s1 - s2 - s0)
            if abs(denominator) > 1e-12 {
                betterTau = Double(tauEstimate) + (s2 - s0) / denominator
            } else {
                betterTau = Double(tauEstimate)
            }
        } else {
            betterTau = Double(tauEstimate)
        }

        let frequency = sampleRate / betterTau
        guard frequency >= minFrequency * 0.9, frequency <= maxFrequency * 1.1 else { return nil }
        return frequency
    }
}

/// Second-order Butterworth lowpass; tames guitar harmonics so YIN can
/// lock onto the fundamental, which laptop mics reproduce only weakly.
private struct BiquadLowpass {
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0
    private var a1: Float = 0, a2: Float = 0
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
    private var configuredRate: Double = 0

    mutating func process(_ input: [Float], sampleRate: Double, cutoff: Double = 1000) -> [Float] {
        if sampleRate != configuredRate {
            configuredRate = sampleRate
            let w = 2 * Double.pi * cutoff / sampleRate
            let alpha = sin(w) / (2 * 0.7071)
            let cosw = cos(w)
            let a0 = 1 + alpha
            b0 = Float(((1 - cosw) / 2) / a0)
            b1 = Float((1 - cosw) / a0)
            b2 = b0
            a1 = Float((-2 * cosw) / a0)
            a2 = Float((1 - alpha) / a0)
            x1 = 0; x2 = 0; y1 = 0; y2 = 0
        }
        var out = [Float](repeating: 0, count: input.count)
        for i in 0..<input.count {
            let x = input[i]
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            out[i] = y
        }
        return out
    }
}

/// Accumulates incoming audio into analysis windows and runs YIN on them.
final class PitchTracker {
    // Large window: the low E string (~82 Hz, lower in drop tunings) needs
    // many periods for a stable estimate, especially via a laptop mic.
    private let windowSize = 8192
    private let hopSize = 2048
    private var buffer: [Float] = []
    // Only true silence is gated. Quiet-but-periodic signals must reach YIN:
    // a guitar through a laptop mic is often no louder than room noise, and
    // periodicity (not level) is what separates a note from that noise.
    private let noiseGateRMS: Float = 0.0005
    private var lowpass = BiquadLowpass()

    /// Called for every analysis window: (frequency or nil, rms level).
    var onResult: ((Double?, Float) -> Void)?

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    func append(_ samples: [Float], sampleRate: Double) {
        buffer.append(contentsOf: lowpass.process(samples, sampleRate: sampleRate))
        while buffer.count >= windowSize {
            let window = Array(buffer[0..<windowSize])
            buffer.removeFirst(hopSize)

            var rms: Float = 0
            vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))

            if rms < noiseGateRMS {
                onResult?(nil, rms)
                continue
            }
            let frequency = YIN.detectPitch(in: window, sampleRate: sampleRate)

            windowCounter += 1
            if frequency != nil || windowCounter % 8 == 0 {
                DebugLog.shared.line(String(
                    format: "window: rms=%.5f freq=%@",
                    rms,
                    frequency.map { String(format: "%.2f", $0) } ?? "nil"
                ))
            }
            onResult?(frequency, rms)
        }
    }

    private var windowCounter = 0
}
