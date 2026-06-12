import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.06, blue: 0.07)
    static let panel = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let panelLight = Color(red: 0.14, green: 0.15, blue: 0.17)
    static let accent = Color(red: 0.16, green: 0.85, blue: 0.49)
    static let warn = Color(red: 1.0, green: 0.62, blue: 0.25)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.6)
    static let gridLine = Color(white: 1.0).opacity(0.035)
}

/// Subtle grid like in the reference design.
struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 44
            var x: CGFloat = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Theme.gridLine), lineWidth: 1)
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(Theme.gridLine), lineWidth: 1)
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}
