import SwiftUI

/// Needle gauge showing deviation in cents (-50...+50) from the target note.
struct GaugeView: View {
    @EnvironmentObject var viewModel: TunerViewModel

    private let maxAngle: Double = 60 // degrees of needle travel each way

    private var hasSignal: Bool { viewModel.frequency != nil }

    private var needleAngle: Double {
        guard hasSignal else { return 0 }
        return viewModel.cents / 50.0 * maxAngle
    }

    private var statusColor: Color {
        guard hasSignal else { return Theme.textSecondary }
        return viewModel.isInTune ? Theme.accent : Theme.warn
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                toleranceArc
                ticks
                needle
            }
            .frame(width: 340, height: 150)

            noteReadout
        }
    }

    // Green arc showing the ±5 cent "in tune" zone.
    private var toleranceArc: some View {
        Canvas { context, size in
            let pivot = CGPoint(x: size.width / 2, y: size.height)
            let rOuter: CGFloat = size.height - 12
            let arcThickness: CGFloat = 16
            let rMid = rOuter - arcThickness / 2
            let halfZone = (5.0 / 50.0 * maxAngle) * .pi / 180

            var path = Path()
            path.addArc(
                center: pivot,
                radius: rMid,
                startAngle: .radians(-.pi / 2 - halfZone),
                endAngle: .radians(-.pi / 2 + halfZone),
                clockwise: false
            )
            context.stroke(
                path,
                with: .color(Theme.accent.opacity(0.25)),
                style: StrokeStyle(lineWidth: arcThickness, lineCap: .round)
            )
        }
    }

    // MARK: - Components

    private var ticks: some View {
        Canvas { context, size in
            let pivot = CGPoint(x: size.width / 2, y: size.height)
            let rOuter = size.height - 6
            for centValue in stride(from: -50.0, through: 50.0, by: 5.0) {
                let isMajor = centValue.truncatingRemainder(dividingBy: 10) == 0
                let isCenter = centValue == 0
                let angle = (centValue / 50.0 * maxAngle) * .pi / 180
                let dx = CGFloat(sin(angle))
                let dy = CGFloat(-cos(angle))
                let length: CGFloat = isCenter ? 22 : (isMajor ? 14 : 8)
                let start = CGPoint(x: pivot.x + dx * (rOuter - length), y: pivot.y + dy * (rOuter - length))
                let end = CGPoint(x: pivot.x + dx * rOuter, y: pivot.y + dy * rOuter)

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)

                let color: Color = isCenter ? Theme.accent : Color(white: isMajor ? 0.55 : 0.3)
                context.stroke(path, with: .color(color), lineWidth: isCenter ? 3 : (isMajor ? 2 : 1))

                if isMajor && !isCenter {
                    let labelRadius: CGFloat = rOuter - length - 14
                    let labelPoint = CGPoint(
                        x: pivot.x + dx * labelRadius,
                        y: pivot.y + dy * labelRadius
                    )
                    context.draw(
                        Text("\(centValue > 0 ? "+" : "")\(Int(centValue))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(white: 0.45)),
                        at: labelPoint
                    )
                }
            }
        }
    }

    private var needle: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(statusColor)
                .frame(width: 4, height: 116)
            Circle()
                .fill(statusColor)
                .frame(width: 14, height: 14)
                .offset(y: 4)
        }
        .opacity(hasSignal ? 1 : 0.35)
        .rotationEffect(.degrees(needleAngle), anchor: .bottom)
        .animation(.easeOut(duration: 0.12), value: needleAngle)
        .animation(.easeOut(duration: 0.2), value: hasSignal)
    }

    private var noteReadout: some View {
        VStack(spacing: 4) {
            if let activeIndex = viewModel.activeString, hasSignal {
                let note = viewModel.selectedTuning.notes[activeIndex]
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(note.name)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)
                    Text("\(note.octave)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(statusColor.opacity(0.7))
                }
                HStack(spacing: 12) {
                    if let frequency = viewModel.frequency {
                        Text(String(format: "%.1f Hz", frequency))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Text(viewModel.isInTune
                         ? "In tune"
                         : String(format: "%+.0f cents", viewModel.cents))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(statusColor)
                }

                // Show actual detected note when it differs from the target string.
                if let actual = viewModel.actualNote,
                   let idx = viewModel.activeString,
                   !viewModel.isInTune,
                   abs(viewModel.cents) > 25,
                   actual.name != viewModel.selectedTuning.notes[idx].name {
                    Text("playing \(actual.display)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(Color(white: 0.3))
                Text("Play a string")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(height: 86)
    }
}
