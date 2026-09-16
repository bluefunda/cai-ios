import SwiftUI

/// Shown while the assistant's response is streaming and no real signal
/// (steps/thinking captions) exists yet — six brand arrows arranged in a
/// ring, each pointing outward like a pinwheel, spinning as one rigid
/// assembly, alongside a caption that cycles through a small set of branded
/// phrases. Reads clearly as "in progress" motion without relying on a
/// fading trail, and the rotating copy keeps longer waits (some agentic
/// queries genuinely take minutes) from staring back with the same static
/// line the whole time.
///
/// Reverted from a brief single-word-style experiment ("Weighing…" etc.)
/// back to these branded phrases per explicit user request.
///
/// Driven by `TimelineView(.animation)` rather than `@State` + `withAnimation`
/// — animating a 0°→360° angle that way silently never moved: SwiftUI's
/// animation only interpolates between the rendered output at the start and
/// end state values, and a full sweep starts and ends at the identical
/// rendered position, so nothing was ever animated. Computing everything
/// directly from wall-clock time on every frame sidesteps that entirely, and
/// lets the pinwheel's rotation and the word rotation share one clock.
struct StreamingIndicator: View {
    // Native artwork aspect ratio (364×190) — see BFArrowMark.
    private static let aspectRatio: CGFloat = 364 / 190
    private static let arrowWidth: CGFloat = 5
    private static let ringRadius: CGFloat = 11
    private static let ringSize: CGFloat = 30
    private static let petalCount = 6
    private static let periodSeconds: Double = 1.6

    private static let words = [
        "Elevating your answer…",
        "Reaching the summit…",
        "Charting the way…",
        "Almost there…",
    ]
    private static let wordIntervalSeconds: Double = 2.5

    private func petal(index: Int) -> some View {
        let placementAngle = Double(index) * (360.0 / Double(Self.petalCount))
        let radians = (placementAngle - 90) * .pi / 180
        return BFArrowMark()
            .fill(BFColor.primary)
            .frame(width: Self.arrowWidth, height: Self.arrowWidth / Self.aspectRatio)
            .rotationEffect(.degrees(placementAngle))
            .offset(x: Self.ringRadius * cos(radians), y: Self.ringRadius * sin(radians))
    }

    private func word(at elapsed: Double) -> String {
        let index = Int(elapsed / Self.wordIntervalSeconds) % Self.words.count
        return Self.words[index]
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let angle = (elapsed.truncatingRemainder(dividingBy: Self.periodSeconds) / Self.periodSeconds) * 360
            let currentWord = word(at: elapsed)

            HStack(spacing: 10) {
                ZStack {
                    ForEach(0..<Self.petalCount, id: \.self) { i in
                        petal(index: i)
                    }
                }
                .frame(width: Self.ringSize, height: Self.ringSize)
                .rotationEffect(.degrees(angle))

                Text(currentWord)
                    .font(.caption)
                    .foregroundStyle(BFColor.primary.opacity(0.85))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: currentWord)
            }
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Generating response")
    }
}
