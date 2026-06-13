import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    referencePitchSection
                    Divider().opacity(0.4)
                    headstockSection
                    Divider().opacity(0.4)
                    algorithmSection
                }
                .padding(28)
            }
        }
        .frame(width: 420)
        .background(Theme.panel)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .foregroundColor(Theme.textSecondary)
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Reference Pitch

    private var referencePitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label(icon: "tuningfork", title: "Reference Pitch",
                  subtitle: "A4 frequency used for all calculations")

            HStack(spacing: 8) {
                ForEach(AppSettings.referencePitchOptions, id: \.self) { hz in
                    PitchChip(hz: hz, isSelected: settings.referencePitch == hz) {
                        settings.referencePitch = hz
                    }
                }
            }
        }
    }

    // MARK: - Headstock Layout

    private var headstockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label(icon: "guitars", title: "Headstock Layout",
                  subtitle: "How string pegs are displayed")

            HStack(spacing: 10) {
                ForEach(HeadstockLayout.allCases, id: \.self) { layout in
                    LayoutChip(
                        layout: layout,
                        isSelected: settings.headstockLayout == layout
                    ) {
                        settings.headstockLayout = layout
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Algorithm

    private var algorithmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label(icon: "waveform.path.ecg", title: "Detection Algorithm",
                  subtitle: "Pitch detection method used for all strings")

            VStack(spacing: 8) {
                ForEach(PitchAlgorithmChoice.allCases, id: \.self) { choice in
                    AlgorithmRow(
                        choice: choice,
                        isSelected: settings.pitchAlgorithm == choice
                    ) {
                        settings.pitchAlgorithm = choice
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func label(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}

// MARK: - PitchChip

private struct PitchChip: View {
    let hz: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(Int(hz))")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                Text("Hz")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 60, height: 48)
            .foregroundColor(isSelected ? Color.black.opacity(0.85) : Theme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Theme.accent : Theme.panelLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.07), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - LayoutChip

private struct LayoutChip: View {
    let layout: HeadstockLayout
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LayoutIcon(layout: layout)
                Text(layout.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundColor(isSelected ? Color.black.opacity(0.85) : Theme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Theme.accent : Theme.panelLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.07), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

/// Tiny schematic icon for each headstock layout.
private struct LayoutIcon: View {
    let layout: HeadstockLayout

    var body: some View {
        Canvas { ctx, size in
            let dot: CGFloat = 3.5
            let positions: [CGPoint]
            switch layout {
            case .threeAndThree:
                // 3 left, 3 right
                positions = [
                    CGPoint(x: 2, y: 2), CGPoint(x: 2, y: 8), CGPoint(x: 2, y: 14),
                    CGPoint(x: 12, y: 2), CGPoint(x: 12, y: 8), CGPoint(x: 12, y: 14)
                ]
            case .sixInARow:
                // 6 left column
                positions = [
                    CGPoint(x: 2, y: 0), CGPoint(x: 2, y: 4),
                    CGPoint(x: 2, y: 8), CGPoint(x: 2, y: 12),
                    CGPoint(x: 2, y: 16), CGPoint(x: 2, y: 20)
                ]
            }
            for p in positions {
                let rect = CGRect(x: p.x, y: p.y, width: dot, height: dot)
                ctx.fill(Path(ellipseIn: rect), with: .foreground)
            }
        }
        .frame(width: 16, height: 22)
    }
}

// MARK: - AlgorithmRow

private struct AlgorithmRow: View {
    let choice: PitchAlgorithmChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 9, height: 9)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(choice.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        if choice == .mpm {
                            Text("recommended")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent.opacity(0.2)))
                                .foregroundColor(Theme.accent)
                        } else if choice == .ptrack {
                            Text("legacy")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.07)))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    Text(choice.description)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Theme.accent.opacity(0.08) : Theme.panelLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
