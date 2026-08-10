import SwiftUI

/// Shown while the assistant's response is streaming — six brand arrows
/// arranged in a ring, each pointing outward like a pinwheel, spinning as one
/// rigid assembly. Reads clearly as "in progress" motion without relying on
/// a fading trail.
///
/// Driven by `TimelineView(.animation)` rather than a `@State` angle animated
/// with `withAnimation(...repeatForever...)` — that approach silently never
/// moved: SwiftUI's animation only interpolates between the rendered output
/// at the start and end state values, and a full 0°→360° sweep starts and
/// ends at the identical rendered position, so nothing was ever animated.
/// Computing the angle directly from wall-clock time on every frame
/// sidesteps that failure mode entirely.
struct StreamingIndicator: View {
    // Native artwork aspect ratio (364×190) — see BFArrowMark.
    private static let aspectRatio: CGFloat = 364 / 190
    private static let arrowWidth: CGFloat = 5
    private static let ringRadius: CGFloat = 11
    private static let ringSize: CGFloat = 30
    private static let petalCount = 6
    private static let periodSeconds: Double = 1.6

    private func petal(index: Int) -> some View {
        let placementAngle = Double(index) * (360.0 / Double(Self.petalCount))
        let radians = (placementAngle - 90) * .pi / 180
        return BFArrowMark()
            .fill(BFColor.primary)
            .frame(width: Self.arrowWidth, height: Self.arrowWidth / Self.aspectRatio)
            .rotationEffect(.degrees(placementAngle))
            .offset(x: Self.ringRadius * cos(radians), y: Self.ringRadius * sin(radians))
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let angle = (elapsed.truncatingRemainder(dividingBy: Self.periodSeconds) / Self.periodSeconds) * 360

            ZStack {
                ForEach(0..<Self.petalCount, id: \.self) { i in
                    petal(index: i)
                }
            }
            .frame(width: Self.ringSize, height: Self.ringSize)
            .rotationEffect(.degrees(angle))
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
