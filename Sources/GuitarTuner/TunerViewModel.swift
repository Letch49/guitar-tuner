import Foundation
import SwiftUI
import AVFoundation
import AppKit
import Combine

@MainActor
final class TunerViewModel: ObservableObject {

    // MARK: - Published state

    @Published var selectedTuning: Tuning {
        didSet {
            guard oldValue != selectedTuning else { return }
            tunedStrings.removeAll()
            pinnedString = nil
            UserDefaults.standard.set(selectedTuning.id, forKey: Self.tuningKey)
            updateDetectorGain()
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
    /// The actual chromatic note closest to the detected frequency,
    /// regardless of the current tuning. Useful for showing "you're playing C#"
    /// even when the target string is E.
    @Published var actualNote: Note?

    var isInTune: Bool { frequency != nil && abs(cents) <= inTuneCents }

    // MARK: - Private

    private static let tuningKey = "lastTuningID"
    private static let deviceKey = "lastInputDeviceUID"

    private let capture = AudioCapture()
    private let tracker = PitchTracker()
    private let tonePlayer = TonePlayer()
    private let settings = AppSettings.shared
    private var settingsCancellables: Set<AnyCancellable> = []

    private let inTuneCents: Double = 5
    private let holdToConfirm: TimeInterval = 0.8

    private var recentFrequencies: [Double] = []
    private var lastDetectionAt: Date = .distantPast
    // Debounce: only add one reading per MPM hop (~46 ms at 50% overlap / 4096 window)
    // so the consistency check requires genuinely separate analysis windows.
    private var lastFrequencyAddedAt: Date = .distantPast
    private var inTuneSince: Date?
    private var silenceTimer: Timer?

    init() {
        let savedTuningID = UserDefaults.standard.string(forKey: Self.tuningKey)
        self.selectedTuning = savedTuningID.flatMap(Tuning.find(id:)) ?? .standard
        updateDetectorGain()

        // Sync static reference pitch on launch
        Note.referencePitch = settings.referencePitch

        // Swap algorithm when user changes the setting
        tracker.algorithm = settings.pitchAlgorithm.makeDetector()
        settings.$pitchAlgorithm
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] choice in
                self?.tracker.algorithm = choice.makeDetector()
                self?.tracker.reset()
            }
            .store(in: &settingsCancellables)

        // Update reference pitch and re-pin if active
        settings.$referencePitch
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPitch in
                guard let self else { return }
                Note.referencePitch = newPitch
                // Re-issue tonePlayer frequency for pinned string with new pitch
                if let pinned = pinnedString {
                    let freq = selectedTuning.notes[pinned].frequency
                    tracker.currentHint = PitchHint(frequency: freq)
                    tonePlayer.play(frequency: freq)
                }
                // Reset smoothing — all target frequencies changed
                recentFrequencies.removeAll()
                frequency = nil
                activeString = nil
                tunedStrings.removeAll()
            }
            .store(in: &settingsCancellables)

        tracker.onResult = { [weak self] frequency, level in
            // onResult is already dispatched to main by PitchTracker
            self?.handleDetection(frequency: frequency, level: level)
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
            tracker.currentHint = nil
        } else {
            pinnedString = index
            recentFrequencies.removeAll()
            lastFrequencyAddedAt = .distantPast
            let freq = selectedTuning.notes[index].frequency
            tracker.currentHint = PitchHint(frequency: freq)
            tonePlayer.play(frequency: freq)
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
        let now = Date()
        lastDetectionAt = now

        // MPM + hint already constrains the search to the pinned string's range,
        // so harmonic folding is generally not needed. We keep a light fold as a
        // safety net for edge cases (e.g. very loud 2nd harmonic).
        var effectiveFrequency = rawFrequency
        if let pinned = pinnedString {
            let target = selectedTuning.notes[pinned].frequency
            for n in 2...4 {
                let folded = rawFrequency / Double(n)
                if abs(1200 * log2(folded / target)) < 30 {
                    effectiveFrequency = folded
                    break
                }
            }
        }

        // MPM fires once per hop (~46 ms at 50% overlap / 4096 window).
        // Keep the debounce guard to prevent a single window from satisfying
        // the consistency check multiple times if callbacks pile up.
        let hopInterval: TimeInterval = 0.046
        if now.timeIntervalSince(lastFrequencyAddedAt) >= hopInterval {
            lastFrequencyAddedAt = now

            // If pitch jumped far away (different string plucked), restart smoothing.
            // Skip this check when pinned — we already know the target string.
            if pinnedString == nil,
               let median = median(of: recentFrequencies),
               abs(1200 * log2(effectiveFrequency / median)) > 80 {
                recentFrequencies.removeAll()
            }
            recentFrequencies.append(effectiveFrequency)
            if recentFrequencies.count > 5 {
                recentFrequencies.removeFirst()
            }
        }

        // Pinned: only need 2 consistent readings (we know what we're looking for).
        // Free: require 4 readings to filter spurious detections.
        let requiredReadings = pinnedString != nil ? 2 : 4
        guard recentFrequencies.count >= requiredReadings,
              let smoothed = median(of: recentFrequencies) else { return }

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
        self.actualNote = chromaticNote(for: smoothed)

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
            actualNote = nil
            cents = 0
            inTuneSince = nil
            recentFrequencies.removeAll()
        }
    }

    /// Scale pre-gain based on the lowest string in the selected tuning.
    /// Lower strings are quieter acoustically, so we boost the signal.
    private func updateDetectorGain() {
        let lowestMidi = selectedTuning.notes.map(\.midi).min() ?? 40
        // Reference: E2 = midi 40 → gain 3.0. Each semitone lower increases by 2^(1/12).
        let gain = Float(min(10.0, 3.0 * pow(2.0, Double(40 - lowestMidi) / 12.0)))
        tracker.gain = gain
        // Clear hint when tuning changes (pinned string is also cleared)
        tracker.currentHint = nil
    }

    /// Returns the chromatic note (nearest semitone) for a given frequency.
    private func chromaticNote(for frequency: Double) -> Note? {
        guard frequency > 0 else { return nil }
        let midi = Int((12 * log2(frequency / Note.referencePitch) + 69).rounded())
        guard midi >= 0 else { return nil }
        return Note(midi: midi)
    }

    private func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
