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

                if let actual = viewModel.actualNote,
                   let idx = viewModel.activeString,
                   !viewModel.isInTune,
                   abs(viewModel.cents) > 25,
                   actual.name != viewModel.selectedTuning.notes[idx].name {
                    Text("playing \(actual.display)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
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

                // Tolerance zone (±5 cents = ±10% of half-width)
                let zoneWidth = w * (5.0 / 50.0)
                Capsule()
                    .fill(Theme.accent.opacity(0.25))
                    .frame(width: zoneWidth * 2, height: 8)

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
        HStack(spacing: 3) {
            // NSImage.size is already 18pt — no extra SwiftUI sizing needed
            Image(nsImage: menuBarIcon)
                .renderingMode(.template)
            if let note = viewModel.actualNote {
                Text("\(note.name)\(note.octave)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
        }
    }

    private var menuBarIcon: NSImage {
        // Apple HIG: menu bar extras use 18×18pt template images.
        // Load the @2x asset (36 physical pixels) and declare its logical size as 18pt —
        // AppKit then applies the correct 2x scale on Retina displays automatically.
        let url = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png")
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MenuBarIcon@2x.png")
        let img: NSImage
        if let loaded = NSImage(contentsOf: url) {
            img = loaded
        } else {
            img = NSImage(systemSymbolName: "guitars", accessibilityDescription: nil)!
        }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }
}

// Needed so the NSStatusBarWindow exclusion compiles.
private class NSStatusBarWindow: NSWindow {}
