import Foundation

/// A musical note identified by its MIDI number.
struct Note: Hashable, Codable {
    let midi: Int

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var frequency: Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    var name: String {
        Note.noteNames[((midi % 12) + 12) % 12]
    }

    var octave: Int {
        midi / 12 - 1
    }

    var display: String {
        "\(name)\(octave)"
    }
}

/// A guitar tuning: 6 notes ordered from string 6 (lowest) to string 1 (highest).
struct Tuning: Identifiable, Hashable {
    let id: String
    let name: String
    let group: String
    let midiNotes: [Int]

    var notes: [Note] { midiNotes.map(Note.init) }

    var notesDisplay: String {
        notes.map(\.display).joined(separator: " ")
    }
}

extension Tuning {
    static let groups = ["Standard", "Drop", "Modal", "Open"]

    static let all: [Tuning] = [
        // Standard: E2 A2 D3 G3 B3 E4
        Tuning(id: "standard", name: "Standard", group: "Standard", midiNotes: [40, 45, 50, 55, 59, 64]),
        Tuning(id: "half-down", name: "Half Step Down", group: "Standard", midiNotes: [39, 44, 49, 54, 58, 63]),
        Tuning(id: "full-down", name: "Full Step Down", group: "Standard", midiNotes: [38, 43, 48, 53, 57, 62]),

        Tuning(id: "drop-d", name: "Drop D", group: "Drop", midiNotes: [38, 45, 50, 55, 59, 64]),
        Tuning(id: "double-drop-d", name: "Double Drop D", group: "Drop", midiNotes: [38, 45, 50, 55, 59, 62]),
        // Drop D tuned down 1/2 step
        Tuning(id: "drop-c-sharp", name: "Drop C#", group: "Drop", midiNotes: [37, 44, 49, 54, 58, 63]),
        Tuning(id: "drop-c", name: "Drop C", group: "Drop", midiNotes: [36, 43, 48, 53, 57, 62]),
        Tuning(id: "drop-b", name: "Drop B", group: "Drop", midiNotes: [35, 42, 47, 52, 56, 61]),
        Tuning(id: "drop-a", name: "Drop A", group: "Drop", midiNotes: [33, 40, 45, 50, 54, 59]),

        Tuning(id: "dadgad", name: "D Modal (DADGAD)", group: "Modal", midiNotes: [38, 45, 50, 55, 57, 62]),
        Tuning(id: "g-modal", name: "G Modal", group: "Modal", midiNotes: [38, 43, 50, 55, 60, 62]),

        Tuning(id: "open-c", name: "Open C", group: "Open", midiNotes: [36, 43, 48, 55, 60, 64]),
        Tuning(id: "open-d", name: "Open D", group: "Open", midiNotes: [38, 45, 50, 54, 57, 62]),
        Tuning(id: "open-e", name: "Open E", group: "Open", midiNotes: [40, 47, 52, 56, 59, 64]),
        Tuning(id: "open-g", name: "Open G", group: "Open", midiNotes: [38, 43, 50, 55, 59, 62]),
        Tuning(id: "open-a", name: "Open A", group: "Open", midiNotes: [40, 45, 52, 57, 61, 64]),
    ]

    static var standard: Tuning { all[0] }

    static func find(id: String) -> Tuning? {
        all.first { $0.id == id }
    }
}
