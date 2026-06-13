import Foundation
import Accelerate

/// Accumulates audio samples into overlapping windows and runs a
/// `PitchDetectionAlgorithm` on each window.
///
/// Default: `MPMDetector`. Swap to `YINDetector()` to A/B test without
/// changing any other code.
///
/// Thread safety: `gain` and `currentHint` may be set from the main thread
/// while `append()` runs on the audio capture queue. A lock serialises those
/// accesses. `reset()` must also be called from the capture queue or while
/// audio is stopped.
final class PitchTracker {

    // MARK: - Configuration (main-thread writes, capture-queue reads)

    /// Active algorithm. Swapping is safe from the main thread;
    /// the capture queue reads the lock-protected `_algorithm` copy.
    var algorithm: any PitchDetectionAlgorithm = MPMDetector() {
        didSet { lock.lock(); _algorithm = algorithm; lock.unlock() }
    }

    /// Pre-gain applied before the algorithm. Auto-adjusted by TunerViewModel
    /// for low tunings (low strings are quieter through a mic).
    var gain: Float = 3.0 {
        didSet { lock.lock(); _gain = gain; lock.unlock() }
    }

    /// Optional hint from TunerViewModel (set when a string is pinned).
    var currentHint: PitchHint? {
        didSet { lock.lock(); _hint = currentHint; lock.unlock() }
    }

    /// Called on the main thread with (detectedFrequency or nil, rms level).
    var onResult: ((Double?, Float) -> Void)?

    // MARK: - Private

    private let windowSize = 4096   // ≈ 93 ms @ 44 100 Hz — covers 2× the period of E2
    private let hopSize    = 2048   // 50 % overlap

    // Lock-protected copies read on the capture queue
    private let lock = NSLock()
    private var _algorithm: any PitchDetectionAlgorithm = MPMDetector()
    private var _gain: Float = 3.0
    private var _hint: PitchHint?

    private var buffer: [Float] = []
    private var window: [Float]   // pre-allocated to avoid heap alloc on hot path
    private var boosted: [Float]  // pre-allocated gain-applied staging buffer
    private var currentSampleRate: Double = 0

    // Silence gate: skip algorithm when RMS is below this level (-46 dBFS).
    private let silenceThreshold: Float = 0.005

    // MARK: - Init

    init() {
        self.window  = [Float](repeating: 0, count: windowSize)
        self.boosted = [Float](repeating: 0, count: 512)   // grows on first large buffer
    }

    // MARK: - Public API

    func reset() {
        buffer.removeAll(keepingCapacity: true)
        lock.lock(); _algorithm.reset(); lock.unlock()
    }

    /// Feed raw audio from `AudioCapture`. Called on the capture queue.
    func append(_ samples: [Float], sampleRate: Double) {
        if sampleRate != currentSampleRate {
            currentSampleRate = sampleRate
            buffer.removeAll(keepingCapacity: true)
            lock.lock(); _algorithm.reset(); lock.unlock()
        }

        // Snapshot shared state atomically
        lock.lock()
        var algo = _algorithm
        let g    = _gain
        let hint = _hint
        lock.unlock()

        // Grow staging buffer if needed (rare — only on first oversized callback)
        if boosted.count < samples.count {
            boosted = [Float](repeating: 0, count: samples.count)
        }

        // Apply pre-gain and compute RMS with vDSP
        var scalar = g
        vDSP_vsmul(samples, 1, &scalar, &boosted, 1, vDSP_Length(samples.count))
        var rms: Float = 0
        vDSP_rmsqv(boosted, 1, &rms, vDSP_Length(samples.count))

        buffer.append(contentsOf: boosted.prefix(samples.count))

        while buffer.count >= windowSize {
            // Copy into pre-allocated window buffer — no heap alloc
            buffer.withUnsafeBufferPointer { src in
                window.withUnsafeMutableBufferPointer { dst in
                    dst.baseAddress!.initialize(from: src.baseAddress!, count: windowSize)
                }
            }
            buffer.removeFirst(hopSize)

            // Skip algorithm on silence to avoid wasted CPU
            var windowRMS: Float = 0
            vDSP_rmsqv(window, 1, &windowRMS, vDSP_Length(windowSize))
            guard windowRMS >= silenceThreshold else {
                DispatchQueue.main.async { [weak self] in self?.onResult?(nil, rms) }
                continue
            }

            let result = algo.process(samples: window, sampleRate: sampleRate, hint: hint)
            let freq: Double? = result.map { $0.frequency }

            DispatchQueue.main.async { [weak self] in self?.onResult?(freq, rms) }
        }
    }
}
