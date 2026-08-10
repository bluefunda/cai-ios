import SwiftUI

/// Shown while the assistant's response is streaming — a single brand arrow
/// orbiting a small ring with a soft trailing fade, rather than a pulsing
/// element in place, which reads as a static logo rather than "in progress."
/// The glyph itself never rotates (only its position sweeps the circle), so
/// the mark never appears sideways or upside down.
struct StreamingIndicator: View {
    // Native artwork aspect ratio (364×190) — see BFArrowMark.
    private static let aspectRatio: CGFloat = 364 / 190
    private static let arrowWidth: CGFloat = 10
    private static let orbitRadius: CGFloat = 7
    private static let orbitSize: CGFloat = 24
    // Trailing echoes, most-recent-first, each further back in the sweep.
    private static let trailOffsets: [Double] = [28, 56]

    @State private var angle: Double = 0 // degrees; 0 = top of the circle

    private func position(atAngleOffset degreesBack: Double) -> CGPoint {
        let radians = (angle - degreesBack - 90) * .pi / 180
        return CGPoint(x: Self.orbitRadius * cos(radians), y: Self.orbitRadius * sin(radians))
    }

    private func arrow(opacity: Double, at point: CGPoint) -> some View {
        BFArrowMark()
            .fill(BFColor.primary)
            .frame(width: Self.arrowWidth, height: Self.arrowWidth / Self.aspectRatio)
            .opacity(opacity)
            .offset(x: point.x, y: point.y)
    }

    var body: some View {
        ZStack {
            ForEach(Array(Self.trailOffsets.enumerated()), id: \.offset) { index, degreesBack in
                arrow(opacity: 0.18 / Double(index + 1), at: position(atAngleOffset: degreesBack))
            }
            arrow(opacity: 0.9, at: position(atAngleOffset: 0))
        }
        .frame(width: Self.orbitSize, height: Self.orbitSize)
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }
}
