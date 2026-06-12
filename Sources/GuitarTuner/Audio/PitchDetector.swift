import Foundation
import Accelerate

/// Monophonic pitch detection using the YIN algorithm
/// (de Cheveigné & Kawahara, 2002).
///
/// The detection core is ported from Beethoven (MIT License,
/// https://github.com/vadymmarkov/Beethoven), YIN implementation by
/// Guillaume Laurent, adapted from pYIN by Matthias Mauch (Centre for
/// Digital Music, Queen Mary, University of London).
///
/// Key behavior inherited from Beethoven: a strict absolute threshold
/// (0.05) for confident detections, and an unconditional fallback to the
/// global minimum of the cumulative mean normalized difference function.
/// Weak fundamentals (low strings through a laptop microphone) rarely dip
/// below any fixed threshold, so rejecting them outright loses the note;
/// temporal-consistency filtering upstream rejects the occasional garbage
/// estimate instead.
enum YIN {
    /// - Returns: detected fundamental frequency in Hz, or nil if no clear pitch.
    static func detectPitch(
        in samples: [Float],
        sampleRate: Double,
        minFrequency: Double = 52,   // just below A1 (55 Hz), above 50 Hz mains hum
        maxFrequency: Double = 600,  // highest open string E4 = 330 Hz, with margin
        threshold: Float = 0.05
    ) -> Double? {
        let half = samples.count / 2
        guard half > 4 else { return nil }

        var yinBuffer = difference(buffer: samples)
        cumulativeDifference(yinBuffer: &yinBuffer)

        let tau = absoluteThreshold(yinBuffer: yinBuffer, withThreshold: threshold)
        guard tau != 0 else { return nil }

        // Beethoven encodes the global-minimum fallback as a negative tau.
        let effectiveTau = abs(tau)
        let interpolatedTau = parabolicInterpolation(yinBuffer: yinBuffer, tau: effectiveTau)
        guard interpolatedTau > 0 else { return nil }

        let frequency = sampleRate / Double(interpolatedTau)
        guard frequency >= minFrequency, frequency <= maxFrequency else { return nil }
        return frequency
    }

    /// Squared difference function d(tau), vDSP-accelerated
    /// (Beethoven's `YINUtil.differenceA`).
    private static func difference(buffer: [Float]) -> [Float] {
        let half = buffer.count / 2
        var result = [Float](repeating: 0, count: half)
        var temp = [Float](repeating: 0, count: half)
        var tempSq = [Float](repeating: 0, count: half)
        let len = vDSP_Length(half)

        buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for tau in 0..<half {
                var sum: Float = 0
                vDSP_vsub(base + tau, 1, base, 1, &temp, 1, len)
                vDSP_vsq(temp, 1, &tempSq, 1, len)
                vDSP_sve(tempSq, 1, &sum, len)
                result[tau] = sum
            }
        }
        return result
    }

    /// Cumulative mean normalized difference (Beethoven's `cumulativeDifference`).
    private static func cumulativeDifference(yinBuffer: inout [Float]) {
        yinBuffer[0] = 1.0
        var runningSum: Float = 0.0
        for tau in 1..<yinBuffer.count {
            runningSum += yinBuffer[tau]
            if runningSum == 0 {
                yinBuffer[tau] = 1
            } else {
                yinBuffer[tau] *= Float(tau) / runningSum
            }
        }
    }

    /// First dip below the threshold, descending to its local minimum.
    /// Returns `-minTau` (global minimum) when nothing dips below the
    /// threshold, 0 when there is no usable minimum at all
    /// (Beethoven's `absoluteThreshold`).
    private static func absoluteThreshold(yinBuffer: [Float], withThreshold threshold: Float) -> Int {
        var tau = 2
        var minTau = 0
        var minVal: Float = 1000.0

        while tau < yinBuffer.count {
            if yinBuffer[tau] < threshold {
                while tau + 1 < yinBuffer.count && yinBuffer[tau + 1] < yinBuffer[tau] {
                    tau += 1
                }
                return tau
            } else {
                if yinBuffer[tau] < minVal {
                    minVal = yinBuffer[tau]
                    minTau = tau
                }
            }
            tau += 1
        }

        if minTau > 0 {
            return -minTau
        }
        return 0
    }

    /// Parabolic interpolation around the minimum for sub-sample precision
    /// (Beethoven's `parabolicInterpolation`).
    private static func parabolicInterpolation(yinBuffer: [Float], tau: Int) -> Float {
        guard tau < yinBuffer.count else {
            return Float(tau)
        }

        var betterTau: Float
        if tau > 0 && tau < yinBuffer.count - 1 {
            let s0 = yinBuffer[tau - 1]
            let s1 = yinBuffer[tau]
            let s2 = yinBuffer[tau + 1]

            var adjustment = (s2 - s0) / (2.0 * (2.0 * s1 - s2 - s0))
            if !adjustment.isFinite || abs(adjustment) > 1 {
                adjustment = 0
            }
            betterTau = Float(tau) + adjustment
        } else {
            betterTau = Float(tau)
        }
        return abs(betterTau)
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
