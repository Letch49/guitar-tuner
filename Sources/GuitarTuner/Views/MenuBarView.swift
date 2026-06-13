import SwiftUI

/// Compact popover shown when clicking the menu bar status item.
struct MenuBarView: View {
    @EnvironmentObject var viewModel: TunerViewModel

    var body: some View {
        VStack(spacing: 0) {
            noteSection
            Divider().opacity(0.3)
            needleSection
            Divider().opacity(0.3)
            footerSection
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Note

    private var noteSection: some View {
        VStack(spacing: 4) {
            if let idx = viewModel.activeString, viewModel.frequency != nil {
                let note = viewModel.selectedTuning.notes[idx]
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(note.name)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)
                    Text("\(note.octave)")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundColor(statusColor.opacity(0.65))
                }
                Text(viewModel.isInTune
                     ? "In tune ✓"
                     : String(format: "%+.0f cents", viewModel.cents))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(statusColor)
            } else {
                Text("—")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(Color(white: 0.35))
                Text("Play a string")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: - Horizontal needle bar

    private var needleSection: some View {
        GeometryReader { geo in
            ZStack {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 6)

                // Colored fill from center to needle
                let w = geo.size.width
                let center = w / 2
                let hasSignal = viewModel.frequency != nil
                let fraction = CGFloat(viewModel.cents / 50.0)   // -1...1
                let offset = fraction * (w / 2 - 12)             // pixels from center

                if hasSignal {
                    Capsule()
                        .fill(statusColor.opacity(0.4))
                        .frame(width: abs(offset), height: 6)
                        .offset(x: offset > 0 ? center - w/2 + abs(offset)/2
                                              : center - w/2 - abs(offset)/2 + abs(offset))
                }

                // Center tick
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 2, height: 14)

                // Needle
                if hasSignal {
                    Capsule()
                        .fill(statusColor)
                        .frame(width: 4, height: 22)
                        .offset(x: offset)
                        .animation(.easeOut(duration: 0.1), value: offset)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 22)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text(viewModel.selectedTuning.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(white: 0.55))

            Spacer()

            Button("Open") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { !($0 is NSStatusBarWindow) }?.makeKeyAndOrderFront(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        guard viewModel.frequency != nil else { return Color(white: 0.35) }
        return viewModel.isInTune ? Theme.accent : Theme.warn
    }
}

/// Dynamic label shown in the macOS menu bar status item.
struct MenuBarLabel: View {
    @EnvironmentObject var viewModel: TunerViewModel

    var body: some View {
        if let idx = viewModel.activeString, viewModel.frequency != nil {
            let note = viewModel.selectedTuning.notes[idx]
            Text("\(note.name)\(note.octave)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        } else {
            Image(systemName: "guitars")
        }
    }
}

// Needed so the NSStatusBarWindow exclusion compiles.
private class NSStatusBarWindow: NSWindow {}
