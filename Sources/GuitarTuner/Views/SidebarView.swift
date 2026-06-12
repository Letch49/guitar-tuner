import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var viewModel: TunerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Tuning.groups, id: \.self) { group in
                    let tunings = Tuning.all.filter { $0.group == group }
                    if !tunings.isEmpty {
                        Text(group.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.2)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 6)

                        ForEach(tunings) { tuning in
                            TuningRow(
                                tuning: tuning,
                                isSelected: viewModel.selectedTuning == tuning
                            ) {
                                viewModel.selectedTuning = tuning
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .frame(width: 290)
        .background(Theme.panel)
    }
}

private struct TuningRow: View {
    let tuning: Tuning
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(tuning.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.accent : Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Text(tuning.notesDisplay)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Theme.accent.opacity(0.12)
                          : hovering ? Color.white.opacity(0.05) : .clear)
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
