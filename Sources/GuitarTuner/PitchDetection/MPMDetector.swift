import Foundation
import Accelerate

/// McLeod Pitch Method (MPM) — "A Smarter Way to Find Pitch" (McLeod & Wyvill, 2005).
///
/// Uses the Normalized Square Difference Function (NSDF):
///
///   NSDF(τ) = 2·ACF(τ) / m(τ)
///
/// where ACF(τ) = Σ x[j]·x[j+τ] and m(τ) = Σ (x[j]² + x[j+τ]²).
///
/// Key properties:
///   • NSDF is bounded to [−1, 1], making threshold selection robust.
///   • Key-maxima peak picking correctly identifies the fundamental even
///     when harmonics dominate.
///   • Parabolic interpolation gives sub-sample (sub-cent) accuracy.
///   • When a PitchHint is supplied, the lag search is restricted to the
///     hint frequency ± tolerance, eliminating octave errors for low strings.
struct MPMDetector: PitchDetectionAlgorithm {

    // MARK: - Parameters

    /// Key-maximum threshold (McLeod paper uses 0.93).
    /// First maximum whose NSDF ≥ cutoff × globalMax is chosen as fundamental.
    var cutoff: Double = 0.93

    /// Minimum NSDF clarity to report a result (rejects noise / aperiodic signals).
    var clarityThreshold: Double = 0.45

    /// Guitar frequency bounds for the lag search in chromatic (no-hint) mode.
    private let minFreqChromatic: Double = 30
    private let maxFreqChromatic: Double = 1400

    // MARK: - PitchDetectionAlgorithm

    mutating func reset() {}   // MPM is stateless per window

    mutating func process(samples: [Float], sampleRate: Double, hint: PitchHint?) -> PitchResult? {
        let n = samples.count
        guard n >= 512 else { return nil }

        // Frequency bounds for lag search
        let minFreq = hint?.minFrequency ?? minFreqChromatic
        let maxFreq = hint?.maxFrequency ?? maxFreqChromatic
        let minLag  = max(1, Int(sampleRate / maxFreq))
        let maxLag  = min(n / 2 - 1, Int(sampleRate / minFreq))
        guard minLag < maxLag else { return nil }

        // 1. Compute NSDF for the relevant lag range
        let nsdf = computeNSDF(samples: samples, minLag: minLag, maxLag: maxLag)

        // 2. Find key maxima (local maxima following a negative-to-positive zero crossing)
        let maxima = keyMaxima(nsdf: nsdf, offset: minLag)

        guard !maxima.isEmpty else { return nil }

        // 3. Pick the best maximum using the threshold
        let globalMax = maxima.map { nsdf[$0 - minLag] }.max() ?? 0
        guard globalMax > 0 else { return nil }
        let threshold = Float(cutoff * Double(globalMax))

        let chosenIdx: Int
        if let hint = hint {
            // String-aware: prefer the lag nearest to the hint frequency
            let hintLag = sampleRate / hint.frequency
            var bestScore = Float(-1)
            var bestIdx   = -1
            for tau in maxima {
                let v = nsdf[tau - minLag]
                guard v >= threshold else { continue }
                let lagD = Double(tau)
                let freq = sampleRate / lagD
                let centsDiff = abs(1200 * log2(freq / hint.frequency))
                // Score blends clarity with proximity to hint
                let proximity = Float(max(0, 1 - centsDiff / hint.toleranceCents))
                let score = v * (0.6 + 0.4 * proximity)
                if score > bestScore {
                    bestScore = score
                    bestIdx   = tau
                }
            }
            // Fallback: first maximum above threshold, closest to hint lag
            if bestIdx == -1 {
                var closest = Double.infinity
                for tau in maxima where nsdf[tau - minLag] >= Float(clarityThreshold) {
                    let dist = abs(Double(tau) - hintLag)
                    if dist < closest {
                        closest = dist
                        bestIdx = tau
                    }
                }
            }
            guard bestIdx != -1 else { return nil }
            chosenIdx = bestIdx
        } else {
            // Chromatic: first maximum above threshold = fundamental (smallest period)
            guard let first = maxima.first(where: { nsdf[$0 - minLag] >= threshold }) else { return nil }
            chosenIdx = first
        }

        let clarity = Double(nsdf[chosenIdx - minLag])

        // 4. Parabolic interpolation for sub-sample accuracy
        let refinedLag = parabolicInterpolation(nsdf: nsdf, tau: chosenIdx, offset: minLag)
        guard refinedLag > 0.5 else { return nil }

        let frequency = sampleRate / refinedLag
        guard frequency >= minFreqChromatic, frequency <= maxFreqChromatic else { return nil }

        return PitchResult(frequency: frequency, clarity: clarity)
    }

    // MARK: - NSDF

    /// Computes NSDF(τ) = 2·ACF(τ) / m(τ) for τ in [minLag, maxLag].
    /// Returns an array indexed from 0, where index 0 corresponds to minLag.
    ///
    /// m(τ) is computed in O(1) per lag using precomputed prefix sums.
    /// ACF(τ) is computed with vDSP_dotpr (vectorised dot product).
    private func computeNSDF(samples: [Float], minLag: Int, maxLag: Int) -> [Float] {
        let n = samples.count
        let count = maxLag - minLag + 1
        var nsdf = [Float](repeating: 0, count: count)

        // Prefix sum of squares: cumSq[k] = Σ_{j=0}^{k-1} x[j]²
        var cumSq = [Double](repeating: 0, count: n + 1)
        for i in 0..<n {
            cumSq[i + 1] = cumSq[i] + Double(samples[i]) * Double(samples[i])
        }
        let totalSq = cumSq[n]

        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }

            for i in 0..<count {
                let tau = minLag + i
                let frames = vDSP_Length(n - tau)
                guard frames > 0 else { break }

                // ACF(τ) via dot product
                var acf: Float = 0
                vDSP_dotpr(base, 1, base + tau, 1, &acf, frames)

                // m(τ) = Σ x[j]² + Σ x[j+τ]² for j = 0..N-τ-1
                //       = cumSq[N-τ] + (totalSq - cumSq[τ])
                let m = cumSq[n - tau] + totalSq - cumSq[tau]

                nsdf[i] = m > 1e-10 ? Float(2.0 * Double(acf) / m) : 0
            }
        }

        return nsdf
    }

    // MARK: - Peak picking

    /// Returns absolute lag indices of "key maxima" — local maxima that
    /// follow a negative-to-positive zero crossing of the NSDF.
    private func keyMaxima(nsdf: [Float], offset: Int) -> [Int] {
        var result: [Int] = []
        let n = nsdf.count
        var i = 0

        // Skip initial positive region (corresponds to τ ≈ 0)
        while i < n - 1, nsdf[i] > 0 { i += 1 }

        while i < n - 1 {
            // Skip negative region until zero crossing upward
            while i < n - 1, nsdf[i] <= 0 { i += 1 }
            if i >= n - 1 { break }

            // Find local maximum in this positive lobe
            var peakVal = Float(-1)
            var peakIdx = i
            while i < n - 1, nsdf[i] > 0 {
                if nsdf[i] > peakVal {
                    peakVal = nsdf[i]
                    peakIdx = i
                }
                i += 1
            }
            if peakVal > 0 { result.append(peakIdx + offset) }
        }

        return result
    }

    // MARK: - Parabolic interpolation

    /// Refines the lag estimate by fitting a parabola through (τ−1, τ, τ+1).
    private func parabolicInterpolation(nsdf: [Float], tau: Int, offset: Int) -> Double {
        let i = tau - offset
        let n = nsdf.count
        guard i > 0, i < n - 1 else { return Double(tau) }

        let y0 = Double(nsdf[i - 1])
        let y1 = Double(nsdf[i])
        let y2 = Double(nsdf[i + 1])

        let denom = 2.0 * (2.0 * y1 - y0 - y2)
        guard abs(denom) > 1e-10 else { return Double(tau) }

        let offset_d = (y2 - y0) / denom
        // Clamp to ±0.5 sample (avoid large extrapolation)
        return Double(tau) + max(-0.5, min(0.5, offset_d))
    }
}
