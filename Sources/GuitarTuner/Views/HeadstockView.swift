import SwiftUI

/// Stylized 3+3 guitar headstock with string labels that light up while tuning.
struct HeadstockView: View {
    @EnvironmentObject var viewModel: TunerViewModel

    // Design-space constants (the whole view is drawn in a 440x470 box and scaled).
    private let designSize = CGSize(width: 440, height: 470)
    private let cx: CGFloat = 220
    private let headTop: CGFloat = 30
    private let headBottom: CGFloat = 330
    private let headWidth: CGFloat = 190
    private let postOffsetX: CGFloat = 64
    private let postYs: [CGFloat] = [110, 185, 260]
    private let labelOffsetX: CGFloat = 150

    /// String indices (0 = low) for the left column, top to bottom.
    private let leftStrings = [2, 1, 0]
    /// String indices for the right column, top to bottom.
    private let rightStrings = [3, 4, 5]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / designSize.width, geo.size.height / designSize.height)
            ZStack {
                neck
                headstock
                strings
                posts
                labels
            }
            .frame(width: designSize.width, height: designSize.height)
            .scaleEffect(scale)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    // MARK: - Geometry helpers

    private func postPosition(stringIndex: Int) -> CGPoint {
        if let row = leftStrings.firstIndex(of: stringIndex) {
            return CGPoint(x: cx - postOffsetX, y: postYs[row])
        }
        let row = rightStrings.firstIndex(of: stringIndex) ?? 0
        return CGPoint(x: cx + postOffsetX, y: postYs[row])
    }

    private func nutX(stringIndex: Int) -> CGFloat {
        // 6 slots across the nut, low string leftmost.
        cx - 37.5 + CGFloat(stringIndex) * 15
    }

    private func stringState(_ index: Int) -> StringState {
        if viewModel.activeString == index, viewModel.frequency != nil {
            return viewModel.isInTune ? .inTune : .active
        }
        if viewModel.tunedStrings.contains(index) {
            return .tuned
        }
        return .idle
    }

    private enum StringState {
        case idle, active, inTune, tuned
    }

    // MARK: - Layers

    private var neck: some View {
        ZStack {
            // Neck wood
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.26, green: 0.16, blue: 0.10),
                                 Color(red: 0.33, green: 0.21, blue: 0.13)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 120, height: designSize.height - headBottom + 10)
                .position(x: cx, y: (headBottom + designSize.height) / 2)
            // Nut
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.85))
                .frame(width: 110, height: 9)
                .position(x: cx, y: headBottom + 4)
        }
    }

    private var headstock: some View {
        HeadstockShape()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.45, green: 0.27, blue: 0.15),
                             Color(red: 0.32, green: 0.18, blue: 0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                HeadstockShape()
                    .stroke(Color.black.opacity(0.5), lineWidth: 2)
            )
            .frame(width: headWidth, height: headBottom - headTop)
            .position(x: cx, y: (headTop + headBottom) / 2)
            .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
    }

    private var strings: some View {
        Canvas { context, _ in
            for index in 0..<6 {
                let post = postPosition(stringIndex: index)
                let slotX = nutX(stringIndex: index)
                var path = Path()
                path.move(to: post)
                path.addLine(to: CGPoint(x: slotX, y: headBottom))
                path.addLine(to: CGPoint(x: slotX, y: designSize.height))

                let state = stringState(index)
                let color: Color
                let width: CGFloat
                switch state {
                case .active:
                    color = Theme.warn
                    width = 2.5
                case .inTune:
                    color = Theme.accent
                    width = 2.5
                case .tuned:
                    color = Theme.accent.opacity(0.55)
                    width = 1.6
                case .idle:
                    color = Color(white: 0.62).opacity(0.8)
                    width = 1.3
                }
                context.stroke(path, with: .color(color), lineWidth: width)
            }
        }
    }

    private var posts: some View {
        ForEach(0..<6, id: \.self) { index in
            let position = postPosition(stringIndex: index)
            let isLeft = position.x < cx
            ZStack {
                // Tuner key sticking out the side
                Capsule()
                    .fill(
                        LinearGradient(colors: [Color(white: 0.75), Color(white: 0.45)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 30, height: 13)
                    .offset(x: isLeft ? -32 : 32)
                // Post
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(white: 0.92), Color(white: 0.55)],
                                       center: .topLeading, startRadius: 1, endRadius: 16)
                    )
                    .frame(width: 19, height: 19)
                Circle()
                    .fill(Color(white: 0.35))
                    .frame(width: 7, height: 7)
            }
            .position(position)
        }
    }

    private var labels: some View {
        ForEach(0..<6, id: \.self) { index in
            let post = postPosition(stringIndex: index)
            let isLeft = post.x < cx
            let labelCenter = CGPoint(x: isLeft ? cx - labelOffsetX : cx + labelOffsetX, y: post.y)
            StringLabel(
                note: viewModel.selectedTuning.notes[index],
                state: stringState(index)
            )
            .position(labelCenter)
        }
    }

    private struct StringLabel: View {
        let note: Note
        let state: StringState

        private var fillColor: Color {
            switch state {
            case .tuned, .inTune: return Theme.accent
            case .active: return Theme.panelLight
            case .idle: return Theme.panelLight
            }
        }

        private var ringColor: Color {
            switch state {
            case .active: return Theme.warn
            case .inTune, .tuned: return Theme.accent
            case .idle: return Color.white.opacity(0.08)
            }
        }

        private var textColor: Color {
            switch state {
            case .tuned, .inTune: return Color.black.opacity(0.85)
            case .active: return Theme.warn
            case .idle: return Theme.textPrimary
            }
        }

        var body: some View {
            ZStack {
                Circle()
                    .fill(fillColor)
                Circle()
                    .strokeBorder(ringColor, lineWidth: 2)
                VStack(spacing: -2) {
                    Text(note.name)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(textColor)
                    if state == .tuned {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(textColor.opacity(0.7))
                    }
                }
            }
            .frame(width: 58, height: 58)
            .animation(.easeOut(duration: 0.15), value: state == .inTune)
        }
    }
}

/// Symmetric 3+3 headstock outline drawn in a unit-ish rect.
private struct HeadstockShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        var path = Path()
        path.move(to: point(0.30, 1.0))
        // Left side: flare out, then taper to the top.
        path.addCurve(to: point(0.06, 0.42), control1: point(0.18, 0.92), control2: point(0.05, 0.66))
        path.addCurve(to: point(0.30, 0.04), control1: point(0.07, 0.20), control2: point(0.16, 0.06))
        // Top with a gentle dip in the middle.
        path.addCurve(to: point(0.50, 0.075), control1: point(0.40, 0.02), control2: point(0.45, 0.075))
        path.addCurve(to: point(0.70, 0.04), control1: point(0.55, 0.075), control2: point(0.60, 0.02))
        // Right side mirrored.
        path.addCurve(to: point(0.94, 0.42), control1: point(0.84, 0.06), control2: point(0.93, 0.20))
        path.addCurve(to: point(0.70, 1.0), control1: point(0.95, 0.66), control2: point(0.82, 0.92))
        path.closeSubpath()
        return path
    }
}
