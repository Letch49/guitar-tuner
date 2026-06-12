import Foundation
import SwiftUI
import AVFoundation
import AppKit

@MainActor
final class TunerViewModel: ObservableObject {

    // MARK: - Published state

    @Published var selectedTuning: Tuning {
        didSet {
            guard oldValue != selectedTuning else { return }
            tunedStrings.removeAll()
            pinnedString = nil
            UserDefaults.standard.set(selectedTuning.id, forKey: Self.tuningKey)
        }
    }

    /// Manually selected string: detection is locked to it and other
    /// strings are ignored. nil = automatic string detection.
    @Published var pinnedString: Int?

    @Published var devices: [AudioInputDevice] = []
    @Published var selectedDeviceUID: String? {
        didSet {
            guard oldValue != selectedDeviceUID else { return }
            if let uid = selectedDeviceUID {
                UserDefaults.standard.set(uid, forKey: Self.deviceKey)
            }
            restartCapture()
        }
    }

    /// Smoothed detected frequency (nil when silent).
    @Published var frequency: Double?
    /// Deviation from the active string target, in cents.
    @Published var cents: Double = 0
    /// Index of the string being tuned, 0 = lowest (6th string).
    @Published var activeString: Int?
    /// Strings already brought in tune in this session.
    @Published var tunedStrings: Set<Int> = []
    @Published var isRunning = false
    @Published var permissionDenied = false
    @Published var captureErrorMessage: String?
    @Published var inputLevel: Float = 0

    var isInTune: Bool { frequency != nil && abs(cents) <= inTuneCents }

    // MARK: - Private

    private static let tuningKey = "lastTuningID"
    private static let deviceKey = "lastInputDeviceUID"

    private let capture = AudioCapture()
    private let tracker = PitchTracker()
    private let tonePlayer = TonePlayer()

    private let inTuneCents: Double = 5
    private let holdToConfirm: TimeInterval = 0.8

    private var recentFrequencies: [Double] = []
    private var lastDetectionAt: Date = .distantPast
    private var inTuneSince: Date?
    private var silenceTimer: Timer?

    init() {
        let savedTuningID = UserDefaults.standard.string(forKey: Self.tuningKey)
        self.selectedTuning = savedTuningID.flatMap(Tuning.find(id:)) ?? .standard

        tracker.onResult = { [weak self] frequency, level in
            DispatchQueue.main.async {
                self?.handleDetection(frequency: frequency, level: level)
            }
        }
        capture.onSamples = { [weak self] samples, sampleRate in
            self?.tracker.append(samples, sampleRate: sampleRate)
        }
        capture.onConfigurationChange = { [weak self] in
            // Device unplugged or its sample rate changed: re-create the engine.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard let self, self.isRunning else { return }
                self.refreshDevices()
                if !self.devices.contains(where: { $0.uid == self.selectedDeviceUID }) {
                    self.selectedDeviceUID = self.devices.first?.uid
                } else {
                    self.startCapture()
                }
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        refreshDevices()
        if selectedDeviceUID == nil {
            selectedDeviceUID = UserDefaults.standard.string(forKey: Self.deviceKey)
                .flatMap { saved in devices.first { $0.uid == saved }?.uid }
                ?? devices.first(where: { $0.id == AudioDeviceManager.defaultInputDeviceID() })?.uid
                ?? devices.first?.uid
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startCapture()
                    } else {
                        self?.permissionDenied = true
                    }
                }
            }
        default:
            permissionDenied = true
        }

        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkSilence() }
        }
    }

    func stopAll() {
        capture.stop()
        silenceTimer?.invalidate()
        silenceTimer = nil
        isRunning = false
    }

    func refreshDevices() {
        devices = AudioDeviceManager.inputDevices()
    }

    func resetTunedStrings() {
        tunedStrings.removeAll()
    }

    /// Tap on a string: pin it (lock tuning to it) and play its reference
    /// note. Tapping the pinned string again unpins it.
    func toggleStringPin(_ index: Int) {
        if pinnedString == index {
            pinnedString = nil
            tonePlayer.stop()
        } else {
            pinnedString = index
            recentFrequencies.removeAll()
            tonePlayer.play(frequency: selectedTuning.notes[index].frequency)
        }
    }

    private func startCapture() {
        tracker.reset()
        do {
            try capture.start(deviceUID: selectedDeviceUID)
            isRunning = true
            captureErrorMessage = nil
        } catch {
            isRunning = false
            captureErrorMessage = error.localizedDescription
        }
    }

    private func restartCapture() {
        guard isRunning || captureErrorMessage != nil else { return }
        startCapture()
    }

    // MARK: - Pitch handling

    private func handleDetection(frequency rawFrequency: Double?, level: Float) {
        inputLevel = level

        guard let rawFrequency else { return }
        lastDetectionAt = Date()

        // If pitch jumped far away (different string plucked), restart smoothing.
        if let median = median(of: recentFrequencies),
           abs(1200 * log2(rawFrequency / median)) > 80 {
            recentFrequencies.removeAll()
        }
        recentFrequencies.append(rawFrequency)
        if recentFrequencies.count > 5 {
            recentFrequencies.removeFirst()
        }
        // Require several consistent readings before showing anything,
        // so short noises and phantom detections don't move the needle.
        guard recentFrequencies.count >= 3, let smoothed = median(of: recentFrequencies) else { return }

        let notes = selectedTuning.notes
        let bestIndex: Int
        if let pinned = pinnedString {
            // Locked to one string: everything is measured against it.
            bestIndex = pinned
        } else {
            var best = 0
            var bestOffset = Double.greatestFiniteMagnitude
            for (index, note) in notes.enumerated() {
                let offset = abs(1200 * log2(smoothed / note.frequency))
                if offset < bestOffset {
                    bestOffset = offset
                    best = index
                }
            }
            bestIndex = best
        }

        let targetCents = max(-50, min(50, 1200 * log2(smoothed / notes[bestIndex].frequency)))
        // Smooth the needle while staying on the same string; jump on string change.
        if frequency != nil, activeString == bestIndex {
            cents = cents * 0.6 + targetCents * 0.4
        } else {
            cents = targetCents
        }
        self.frequency = smoothed
        self.activeString = bestIndex

        if abs(cents) <= inTuneCents {
            if let since = inTuneSince {
                if Date().timeIntervalSince(since) >= holdToConfirm, !tunedStrings.contains(bestIndex) {
                    tunedStrings.insert(bestIndex)
                    NSSound(named: "Glass")?.play()
                }
            } else {
                inTuneSince = Date()
            }
        } else {
            inTuneSince = nil
        }
    }

    private func checkSilence() {
        guard frequency != nil else { return }
        if Date().timeIntervalSince(lastDetectionAt) > 0.7 {
            frequency = nil
            activeString = nil
            cents = 0
            inTuneSince = nil
            recentFrequencies.removeAll()
        }
    }

    private func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
