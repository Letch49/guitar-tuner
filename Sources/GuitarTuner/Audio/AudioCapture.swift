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
    // A dedicated queue for session start/stop — Apple explicitly warns that
    // calling startRunning() / stopRunning() on the main thread can crash.
    private let sessionQueue = DispatchQueue(label: "guitartuner.session")
    private var observers: [NSObjectProtocol] = []

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
        // Build the session on the calling thread (configuration is fast),
        // but start/stop running must happen off the main thread.
        stopSync()

        let device: AVCaptureDevice? = deviceUID
            .flatMap { AVCaptureDevice(uniqueID: $0) }
            ?? .default(for: .audio)
        guard let device else { throw CaptureError.deviceNotFound }

        let session = AVCaptureSession()
        session.beginConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotUseDevice }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
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
        self.session = session

        // startRunning() blocks until the session is ready — must not run on
        // the main thread or it will cause a watchdog crash.
        sessionQueue.async { [weak self] in
            session.startRunning()
            self?.registerSessionObservers(for: session)
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let s = session
        session = nil
        sessionQueue.async { s?.stopRunning() }
    }

    // Synchronous stop used before reconfiguring — waits for the session queue
    // to finish so we don't overlap start/stop calls.
    private func stopSync() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let s = session
        session = nil
        sessionQueue.sync { s?.stopRunning() }
    }

    private func registerSessionObservers(for session: AVCaptureSession) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .AVCaptureSessionRuntimeError, object: session, queue: nil
            ) { [weak self] _ in self?.onConfigurationChange?() },
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.onConfigurationChange?() },
        ]
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
        onSamples?(mono, sampleRate)
    }
}
