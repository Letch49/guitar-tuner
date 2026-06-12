import Foundation
import AVFoundation
import CoreMedia
import Accelerate

/// Captures mono audio from a chosen input device using AVCaptureSession.
///
/// AVCaptureSession is used instead of AVAudioEngine because the engine's
/// inputNode caches the format of the default device and silently delivers
/// no data when switched to a device with a different sample rate or
/// channel count (typical for USB audio interfaces).
final class AudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var session: AVCaptureSession?
    private let sampleQueue = DispatchQueue(label: "guitartuner.capture")
    private var observers: [NSObjectProtocol] = []
    private var bufferCount = 0

    /// Called on the capture queue with mono samples and the sample rate.
    var onSamples: (([Float], Double) -> Void)?
    /// Called when the device disappears or the session fails; the owner should restart.
    var onConfigurationChange: (() -> Void)?

    enum CaptureError: LocalizedError {
        case deviceNotFound
        case cannotUseDevice

        var errorDescription: String? {
            switch self {
            case .deviceNotFound: return "Input device not found."
            case .cannotUseDevice: return "Could not use the selected input device."
            }
        }
    }

    func start(deviceUID: String?) throws {
        stop()

        // AVCaptureDevice.uniqueID matches the Core Audio device UID.
        let device: AVCaptureDevice? = deviceUID
            .flatMap { AVCaptureDevice(uniqueID: $0) }
            ?? .default(for: .audio)
        DebugLog.shared.line(
            "capture start: requested uid=\(deviceUID ?? "<default>") "
            + "resolved=\(device?.localizedName ?? "nil") (\(device?.uniqueID ?? "-"))"
        )
        guard let device else { throw CaptureError.deviceNotFound }
        bufferCount = 0

        let session = AVCaptureSession()
        session.beginConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotUseDevice }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        // Request float32 interleaved PCM at the device's native rate and channel count.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else { throw CaptureError.cannotUseDevice }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()
        self.session = session

        DebugLog.shared.line("session running=\(session.isRunning)")

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .AVCaptureSessionRuntimeError, object: session, queue: nil
            ) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] ?? "unknown"
                DebugLog.shared.line("session runtime error: \(error)")
                self?.onConfigurationChange?()
            },
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.onConfigurationChange?()
            },
        ]
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        session?.stopRunning()
        session = nil
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        else { return }

        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let sampleRate = asbd.mSampleRate
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, sampleRate > 0,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let data = try? blockBuffer.dataBytes()
        else { return }

        let mono: [Float] = data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Float.self)
            guard let base = samples.baseAddress, samples.count >= frames * channels else { return [] }
            if channels == 1 {
                return Array(samples.prefix(frames))
            }
            // The guitar is usually plugged into a single input of the interface,
            // so use the loudest channel instead of mixing them all down.
            var bestChannel = 0
            var bestRMS: Float = -1
            for ch in 0..<channels {
                var rms: Float = 0
                vDSP_rmsqv(base + ch, vDSP_Stride(channels), &rms, vDSP_Length(frames))
                if rms > bestRMS {
                    bestRMS = rms
                    bestChannel = ch
                }
            }
            var out = [Float](repeating: 0, count: frames)
            for i in 0..<frames {
                out[i] = samples[i * channels + bestChannel]
            }
            return out
        }

        guard !mono.isEmpty else { return }

        bufferCount += 1
        if bufferCount == 1 || bufferCount % 200 == 0 {
            var rms: Float = 0
            vDSP_rmsqv(mono, 1, &rms, vDSP_Length(mono.count))
            DebugLog.shared.line(String(
                format: "buffer #%d: sr=%.0f ch=%d frames=%d rms=%.5f",
                bufferCount, sampleRate, channels, frames, rms
            ))
        }
        onSamples?(mono, sampleRate)
    }
}
