import SwiftUI

/// Shown while the assistant's response is streaming — a single brand arrow
/// orbiting a small ring with a soft trailing fade, rather than a pulsing
/// element in place, which reads as a static logo rather than "in progress."
/// The glyph itself never rotates (only its position sweeps the circle), so
/// the mark never appears sideways or upside down.
///
/// Driven by `TimelineView(.animation)` rather than a `@State` angle animated
/// with `withAnimation(...repeatForever...)`. That approach looked identical
/// at rest: SwiftUI's animation only interpolates between the rendered output
/// at the start and end values, and `cos`/`sin` at 0° and 360° are the same
/// number — so the "animation" ran from one identical position to itself,
/// and the arrow just sat frozen at the top of the orbit. Computing the angle
/// directly from wall-clock time on every frame sidesteps that entirely.
struct StreamingIndicator: View {
    // Native artwork aspect ratio (364×190) — see BFArrowMark.
    private static let aspectRatio: CGFloat = 364 / 190
    private static let arrowWidth: CGFloat = 10
    private static let orbitRadius: CGFloat = 7
    private static let orbitSize: CGFloat = 24
    private static let periodSeconds: Double = 1.1
    // Trailing echoes, most-recent-first, each further back in the sweep.
    private static let trailOffsets: [Double] = [28, 56]

    private func position(angle: Double, atAngleOffset degreesBack: Double) -> CGPoint {
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
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let angle = (elapsed.truncatingRemainder(dividingBy: Self.periodSeconds) / Self.periodSeconds) * 360

            ZStack {
                ForEach(Array(Self.trailOffsets.enumerated()), id: \.offset) { index, degreesBack in
                    arrow(opacity: 0.18 / Double(index + 1), at: position(angle: angle, atAngleOffset: degreesBack))
                }
                arrow(opacity: 0.9, at: position(angle: angle, atAngleOffset: 0))
            }
            .frame(width: Self.orbitSize, height: Self.orbitSize)
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
