import SwiftUI

/// Stylized guitar headstock with string labels that light up while tuning.
/// Supports 3+3 (symmetric) and 6-in-a-row (Fender-style) layouts via AppSettings.
struct HeadstockView: View {
    @EnvironmentObject var viewModel: TunerViewModel
    @ObservedObject private var settings = AppSettings.shared

    // Design-space constants (the whole view is drawn in a 440x470 box and scaled).
    private let designSize = CGSize(width: 440, height: 470)
    private let cx: CGFloat = 220
    private let headTop: CGFloat = 30
    private let headBottom: CGFloat = 330
    private let headWidth: CGFloat = 190
    private let postOffsetX: CGFloat = 64
    private let labelOffsetX: CGFloat = 150

    // 3+3: three rows on each side
    private let postYs33: [CGFloat] = [110, 185, 260]
    /// String indices (0 = low) for the left column (3+3), top to bottom.
    private let leftStrings33 = [2, 1, 0]
    /// String indices for the right column (3+3), top to bottom.
    private let rightStrings33 = [3, 4, 5]

    // 6-in-a-row (Fender/Strat style):
    //   • peg column at cx-55 = 165 — inside the headstock shape throughout
    //   • string 0 (low E) near the nut (bottom), string 5 (high E) near the tip (top)
    //   • tuner keys offset left 32 px, protruding through the left edge (authentic look)
    // Even 52 px spacing so the 44 px note circles never overlap.
    private let postYs6: [CGFloat] = [305, 253, 201, 149, 97, 45]
    private let postX6:  CGFloat   = 165   // cx - 55, inside the shape so keys land on wood
    private let label6Diameter: CGFloat = 44
    private let label6OffsetX:  CGFloat  = 140  // labels at cx-140 = 80

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / designSize.width, geo.size.height / designSize.height)
            ZStack {
                neck
                headstockShape
                strings
                posts
                labels
            }
            .frame(width: designSize.width, height: designSize.height)
            .scaleEffect(scale)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .animation(.easeInOut(duration: 0.25), value: settings.headstockLayout)
    }

    // MARK: - Geometry helpers

    private func postPosition(stringIndex: Int) -> CGPoint {
        switch settings.headstockLayout {
        case .threeAndThree:
            if let row = leftStrings33.firstIndex(of: stringIndex) {
                return CGPoint(x: cx - postOffsetX, y: postYs33[row])
            }
            let row = rightStrings33.firstIndex(of: stringIndex) ?? 0
            return CGPoint(x: cx + postOffsetX, y: postYs33[row])
        case .sixInARow:
            return CGPoint(x: postX6, y: postYs6[stringIndex])
        }
    }

    private func nutX(stringIndex: Int) -> CGFloat {
        // 6 evenly-spaced nut slots centred on cx (same for both layouts).
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

    @ViewBuilder
    private var headstockShape: some View {
        let wood = LinearGradient(
            colors: [Color(red: 0.45, green: 0.27, blue: 0.15),
                     Color(red: 0.32, green: 0.18, blue: 0.10)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        if settings.headstockLayout == .threeAndThree {
            ThreeThreeHeadstockShape()
                .fill(wood)
                .overlay(ThreeThreeHeadstockShape().stroke(Color.black.opacity(0.5), lineWidth: 2))
                .frame(width: headWidth, height: headBottom - headTop)
                .position(x: cx, y: (headTop + headBottom) / 2)
                .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        } else {
            // 6-in-a-row: frame spans x=[110,290] y=[20,330], size 180×310,
            // centred at (200, 175).  The shape's normalised bezier matches the
            // Strat S-curve from the Python mock exactly.
            SixInARowHeadstockShape()
                .fill(wood)
                .overlay(SixInARowHeadstockShape().stroke(Color.black.opacity(0.5), lineWidth: 2))
                .frame(width: 180, height: 310)
                .position(x: 200, y: 175)
                .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        }
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
                let isPinned = viewModel.pinnedString == index
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
                    color = isPinned ? Theme.accent.opacity(0.7) : Color(white: 0.62).opacity(0.8)
                    width = isPinned ? 2.0 : 1.3
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

    private func labelX(stringIndex: Int) -> CGFloat {
        switch settings.headstockLayout {
        case .threeAndThree:
            return postPosition(stringIndex: stringIndex).x < cx ? cx - labelOffsetX : cx + labelOffsetX
        case .sixInARow:
            return cx - label6OffsetX
        }
    }

    private var labelDiameter: CGFloat {
        settings.headstockLayout == .sixInARow ? label6Diameter : 58
    }

    private var labels: some View {
        ForEach(0..<6, id: \.self) { index in
            let post = postPosition(stringIndex: index)
            StringLabel(
                note: viewModel.selectedTuning.notes[index],
                state: stringState(index),
                isPinned: viewModel.pinnedString == index,
                diameter: labelDiameter
            ) {
                viewModel.toggleStringPin(index)
            }
            .position(CGPoint(x: labelX(stringIndex: index), y: post.y))
        }
    }

    private struct StringLabel: View {
        let note: Note
        let state: StringState
        let isPinned: Bool
        let diameter: CGFloat
        let action: () -> Void

        @State private var hovering = false

        private var fillColor: Color {
            switch state {
            case .tuned, .inTune: return Theme.accent
            case .active: return Theme.panelLight
            case .idle: return Theme.panelLight
            }
        }

        private var ringColor: Color {
            if isPinned { return Theme.accent }
            switch state {
            case .active: return Theme.warn
            case .inTune, .tuned: return Theme.accent
            case .idle: return hovering ? Color.white.opacity(0.3) : Color.white.opacity(0.08)
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
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(fillColor)
                    Circle()
                        .strokeBorder(ringColor, lineWidth: isPinned ? 3 : 2)
                    VStack(spacing: -2) {
                        Text(note.name)
                            .font(.system(size: diameter * 0.345, weight: .semibold, design: .rounded))
                            .foregroundColor(textColor)
                        if state == .tuned {
                            Image(systemName: "checkmark")
                                .font(.system(size: diameter * 0.155, weight: .bold))
                                .foregroundColor(textColor.opacity(0.7))
                        } else if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: diameter * 0.14, weight: .bold))
                                .foregroundColor(textColor.opacity(0.7))
                        }
                    }
                }
                .frame(width: diameter, height: diameter)
                .shadow(color: isPinned ? Theme.accent.opacity(0.55) : .clear, radius: isPinned ? 9 : 0)
                .scaleEffect(hovering && !isPinned ? 1.06 : 1.0)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(isPinned
                  ? "Unpin string (back to auto detection)"
                  : "Pin this string and play its reference note")
            .animation(.easeOut(duration: 0.15), value: state == .inTune)
            .animation(.easeOut(duration: 0.15), value: isPinned)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Symmetric 3+3 headstock outline.
private struct ThreeThreeHeadstockShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        var path = Path()
        path.move(to: point(0.30, 1.0))
        path.addCurve(to: point(0.06, 0.42), control1: point(0.18, 0.92), control2: point(0.05, 0.66))
        path.addCurve(to: point(0.30, 0.04), control1: point(0.07, 0.20), control2: point(0.16, 0.06))
        path.addCurve(to: point(0.50, 0.075), control1: point(0.40, 0.02), control2: point(0.45, 0.075))
        path.addCurve(to: point(0.70, 0.04), control1: point(0.55, 0.075), control2: point(0.60, 0.02))
        path.addCurve(to: point(0.94, 0.42), control1: point(0.84, 0.06), control2: point(0.93, 0.20))
        path.addCurve(to: point(0.70, 1.0), control1: point(0.95, 0.66), control2: point(0.82, 0.92))
        path.closeSubpath()
        return path
    }
}

/// Fender/Strat-style 6-in-a-row headstock outline.
/// Frame: 180 × 310 pt, positioned at (200, 175) in the 440×470 design space.
/// That places the frame x-range [110, 290], y-range [20, 330].
///
/// Normalised coordinates are derived from the Python mock that matches a real
/// guitar headstock photo:
///   • right side is nearly straight (slight flare)
///   • top is a gentle dome
///   • left side has the characteristic Strat S-curve: bows outward, then
///     curves inward back to the nut corner
private struct SixInARowHeadstockShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        // Nut-right corner
        path.move(to: p(0.917, 1.0))
        // Right side (treble) up — long and nearly straight, slight taper near the top
        path.addCurve(to: p(0.822, 0.058),
                      control1: p(0.956, 0.677),
                      control2: p(0.967, 0.323))
        // Top dome, right → left
        path.addCurve(to: p(0.011, 0.161),
                      control1: p(0.639, 0.013),
                      control2: p(0.306, 0.019))
        // Left side (bass / peg side) down — stays wide so keys land on wood
        path.addCurve(to: p(0.044, 0.903),
                      control1: p(-0.022, 0.419),
                      control2: p(-0.011, 0.677))
        // Taper in to the nut-left corner below the lowest peg
        path.addCurve(to: p(0.306, 1.0),
                      control1: p(0.167, 0.974),
                      control2: p(0.222, 1.0))
        path.closeSubpath()
        return path
    }
}
