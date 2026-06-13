import Foundation
import Combine

// MARK: - Enums

enum HeadstockLayout: String, CaseIterable {
    case threeAndThree = "3+3"
    case sixInARow     = "6 in a row"
}

enum PitchAlgorithmChoice: String, CaseIterable {
    case mpm
    case yin
    case ptrack

    var displayName: String {
        switch self {
        case .mpm:    return "MPM"
        case .yin:    return "YIN"
        case .ptrack: return "PTrack"
        }
    }

    var description: String {
        switch self {
        case .mpm:    return "McLeod Pitch Method — best for guitar"
        case .yin:    return "YIN / CMNDF — alternative algorithm"
        case .ptrack: return "FFT-based partial tracker (legacy)"
        }
    }

    func makeDetector() -> any PitchDetectionAlgorithm {
        switch self {
        case .mpm:    return MPMDetector()
        case .yin:    return YINDetector()
        case .ptrack: return PTrackDetector()
        }
    }
}

// MARK: - AppSettings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let referencePitchOptions: [Double] = [432, 440, 441, 442, 443]

    @Published var referencePitch: Double {
        didSet { UserDefaults.standard.set(referencePitch, forKey: "referencePitch") }
    }

    @Published var headstockLayout: HeadstockLayout {
        didSet { UserDefaults.standard.set(headstockLayout.rawValue, forKey: "headstockLayout") }
    }

    @Published var pitchAlgorithm: PitchAlgorithmChoice {
        didSet { UserDefaults.standard.set(pitchAlgorithm.rawValue, forKey: "pitchAlgorithm") }
    }

    private init() {
        let savedPitch = UserDefaults.standard.double(forKey: "referencePitch")
        referencePitch = AppSettings.referencePitchOptions.contains(savedPitch) ? savedPitch : 440.0

        let layoutRaw = UserDefaults.standard.string(forKey: "headstockLayout") ?? ""
        headstockLayout = HeadstockLayout(rawValue: layoutRaw) ?? .threeAndThree

        let algoRaw = UserDefaults.standard.string(forKey: "pitchAlgorithm") ?? ""
        pitchAlgorithm = PitchAlgorithmChoice(rawValue: algoRaw) ?? .mpm
    }
}
