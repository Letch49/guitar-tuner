import Foundation
import AVFoundation

/// Plays a short plucked-string-like reference tone for a given frequency.
final class TonePlayer {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let sampleRate: Double = 44100

    // Written from the main thread, read from the render thread.
    // Worst case of a race is one slightly off sample, which is inaudible.
    private var phase: Double = 0
    private var frequency: Double = 0
    private var samplesPlayed: Int = 0
    private var isActive = false

    private let duration: Double = 2.0

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = ablPointer.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            if !self.isActive {
                for i in 0..<Int(frameCount) { out[i] = 0 }
                return noErr
            }

            let totalSamples = Int(self.duration * self.sampleRate)
            let phaseStep = 2 * Double.pi * self.frequency / self.sampleRate

            for i in 0..<Int(frameCount) {
                if self.samplesPlayed >= totalSamples {
                    self.isActive = false
                    out[i] = 0
                    continue
                }
                let t = Double(self.samplesPlayed) / self.sampleRate
                // Pluck-like envelope: fast attack, exponential decay.
                let attack = min(1.0, t / 0.005)
                let envelope = attack * exp(-2.2 * t)
                // Fundamental plus a few decaying harmonics for a string-ish timbre.
                let p = self.phase
                let sample = sin(p)
                    + 0.5 * sin(2 * p) * exp(-1.5 * t)
                    + 0.22 * sin(3 * p) * exp(-2.5 * t)
                    + 0.1 * sin(4 * p) * exp(-3.5 * t)
                out[i] = Float(sample * envelope * 0.24)

                self.phase += phaseStep
                if self.phase > 2 * Double.pi {
                    self.phase -= 2 * Double.pi
                }
                self.samplesPlayed += 1
            }
            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func play(frequency: Double) {
        if !engine.isRunning {
            try? engine.start()
        }
        self.frequency = frequency
        self.phase = 0
        self.samplesPlayed = 0
        self.isActive = true
    }

    func stop() {
        isActive = false
    }
}
