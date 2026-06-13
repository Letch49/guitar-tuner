import Foundation
import Accelerate

/// YIN pitch detector — de Cheveigné & Kawahara, 2002.
///
/// Uses the Cumulative Mean Normalized Difference Function (CMNDF):
///
///   d(τ)  = Σ (x[j] − x[j+τ])²          (difference function)
///   d'(τ) = d(τ) / (1/τ · Σ_{j=1}^{τ} d(j))   (CMNDF)
///
/// Guitar Tuna's pipeline matches this closely:
///   noise gate → CMNDF → dynamic threshold → parabolic interpolation
///
/// Dynamic threshold: starts at 0.10; if no valley found, raises to 0.15,
/// 0.20 … 0.40.  This handles quiet / noisy signals better than a fixed value.
struct YINDetector: PitchDetectionAlgorithm {

    // MARK: - Parameters

    /// Starting threshold for valley search (YIN paper uses 0.10).
    var baseThreshold: Double = 0.10
    /// Raise threshold by this step when no valley found below current value.
    var thresholdStep: Double = 0.05
    /// Maximum threshold before giving up (avoids unreliable detections).
    var maxThreshold:  Double = 0.40

    /// Minimum clarity (= 1 − d'(τ_best)) to accept a result.
    var clarityThreshold: Double = 0.45

    private let minFreqChromatic: Double = 30
    private let maxFreqChromatic: Double = 1400

    // MARK: - PitchDetectionAlgorithm

    mutating func reset() {}   // stateless per window

    mutating func process(samples: [Float], sampleRate: Double, hint: PitchHint?) -> PitchResult? {
        let n = samples.count
        guard n >= 512 else { return nil }

        let minFreq = hint?.minFrequency ?? minFreqChromatic
        let maxFreq = hint?.maxFrequency ?? maxFreqChromatic
        let minLag  = max(1, Int(sampleRate / maxFreq))
        let maxLag  = min(n / 2 - 1, Int(sampleRate / minFreq))
        guard minLag < maxLag else { return nil }

        // 1. Compute difference function d(τ) and CMNDF d'(τ)
        let cmndf = computeCMNDF(samples: samples, minLag: minLag, maxLag: maxLag)

        // 2. Dynamic threshold valley search
        var bestLag: Int? = nil
        var threshold = baseThreshold
        while threshold <= maxThreshold {
            bestLag = firstValleyBelow(cmndf: cmndf, threshold: threshold, offset: minLag)
            if bestLag != nil { break }
            threshold += thresholdStep
        }

        guard let chosenLag = bestLag else { return nil }

        let dVal = Double(cmndf[chosenLag - minLag])
        let clarity = max(0, 1.0 - dVal)   // CMNDF = 0 → perfect periodicity → clarity 1
        guard clarity >= clarityThreshold else { return nil }

        // 3. Parabolic interpolation for sub-sample accuracy
        let refined = parabolicInterpolation(cmndf: cmndf, tau: chosenLag, offset: minLag)
        guard refined > 0.5 else { return nil }

        let frequency = sampleRate / refined
        guard frequency >= minFreqChromatic, frequency <= maxFreqChromatic else { return nil }

        return PitchResult(frequency: frequency, clarity: clarity)
    }

    // MARK: - CMNDF

    /// Returns CMNDF indexed from 0, where index 0 corresponds to minLag.
    private func computeCMNDF(samples: [Float], minLag: Int, maxLag: Int) -> [Float] {
        let n = samples.count
        let count = maxLag - minLag + 1

        var cumSq = [Double](repeating: 0, count: n + 1)
        for i in 0..<n {
            cumSq[i + 1] = cumSq[i] + Double(samples[i]) * Double(samples[i])
        }
        let totalSq = cumSq[n]

        // d(τ) for τ = minLag..maxLag (skip lags below the guitar frequency range)
        var d = [Double](repeating: 0, count: count)
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for i in 0..<count {
                let tau = minLag + i
                let frames = vDSP_Length(n - tau)
                guard frames > 0 else { break }
                var acf: Float = 0
                vDSP_dotpr(base, 1, base + tau, 1, &acf, frames)
                let m = cumSq[n - tau] + totalSq - cumSq[tau]
                d[i] = m - 2.0 * Double(acf)
            }
        }

        // CMNDF over the computed range.
        // The cumulative denominator is bootstrapped from minLag, so d'(τ) is
        // normalised relative to the lags we actually examine.
        var result = [Float](repeating: 1, count: count)
        var cumSum = 0.0
        for i in 0..<count {
            cumSum += d[i]
            let tau = minLag + i
            result[i] = cumSum > 0 ? Float(Double(tau) * d[i] / cumSum) : 1.0
        }
        return result
    }

    // MARK: - Valley picking

    /// Returns the lag index of the first CMNDF valley (local minimum)
    /// that falls below `threshold`.
    private func firstValleyBelow(cmndf: [Float], threshold: Double, offset: Int) -> Int? {
        let n = cmndf.count
        var i = 1
        while i < n - 1 {
            // Descending slope
            while i < n - 1, cmndf[i] >= cmndf[i - 1] { i += 1 }
            if i >= n - 1 { break }

            // Found a local minimum — find its trough
            while i < n - 1, cmndf[i] <= cmndf[i + 1] { i += 1 }

            if Double(cmndf[i]) < threshold { return i + offset }
            i += 1
        }
        return nil
    }

    // MARK: - Parabolic interpolation

    private func parabolicInterpolation(cmndf: [Float], tau: Int, offset: Int) -> Double {
        let i = tau - offset
        let n = cmndf.count
        guard i > 0, i < n - 1 else { return Double(tau) }

        let y0 = Double(cmndf[i - 1])
        let y1 = Double(cmndf[i])
        let y2 = Double(cmndf[i + 1])

        // Parabola minimum (CMNDF has minima at pitch periods)
        let denom = y0 - 2.0 * y1 + y2
        guard abs(denom) > 1e-10 else { return Double(tau) }

        let delta = 0.5 * (y0 - y2) / denom
        return Double(tau) + max(-0.5, min(0.5, delta))
    }
}
