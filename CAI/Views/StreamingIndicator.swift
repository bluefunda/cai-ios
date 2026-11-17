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

    /// When this indicator appeared (the reply was sent). Phrases are timed from here, not from
    /// the wall clock, so every reply starts on the first phrase.
    @State private var startedAt = Date()

    /// The phrases play once, in order, then hold on the last ("Almost there…") — looping back
    /// to "Elevating your answer…" read as if the wait had started over.
    private func word(at sinceStart: Double) -> String {
        let index = min(Int(max(0, sinceStart) / Self.wordIntervalSeconds), Self.words.count - 1)
        return Self.words[index]
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let angle = (elapsed.truncatingRemainder(dividingBy: Self.periodSeconds) / Self.periodSeconds) * 360
            let currentWord = word(at: context.date.timeIntervalSince(startedAt))

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

/// Three dots pulsing in turn under an answer that is still streaming (see
/// AnswerWithInlineStepsView): the reply isn't finished while the model reads tool results or
/// thinks between parts of its answer. Holds still with Reduce Motion.
struct StillWorkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let periodSeconds: Double = 1.2

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(BFColor.primary)
                        .frame(width: 6, height: 6)
                        .opacity(reduceMotion ? 0.7 : Self.opacity(at: time, index: index))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Still working")
    }

    /// 0.35 → 1 → 0.35 once per period, each dot a fifth of a period behind the one before.
    static func opacity(at time: Double, index: Int) -> Double {
        let phase = (time / periodSeconds - Double(index) * 0.2).truncatingRemainder(dividingBy: 1)
        let wave = (1 - cos(2 * .pi * (phase < 0 ? phase + 1 : phase))) / 2
        return 0.35 + 0.65 * wave
    }
}

/// Layout shared by the live rows (the thinking card's header, a mid-answer step group).
enum LiveRow {
    /// Between the dots, the text and the timer.
    static let spacing: CGFloat = 8
    /// The dots (3 × 6pt + 2 × 4pt) plus `spacing`: a box under a live row starts under its text.
    static let indent: CGFloat = 26 + spacing
    /// A step box stops here on a wide window (iPad, Mac) — about 90 characters of its text, so
    /// it reads as a note rather than a banner. Narrower columns use their full width.
    static let boxMaxWidth: CGFloat = 680

    /// "12s", "1m 5s".
    static func elapsedLabel(seconds: Int) -> String {
        let seconds = max(0, seconds)
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }
}

/// Seconds since `since`, ticking once a second: how long a live row has been working.
struct LiveTimer: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(LiveRow.elapsedLabel(seconds: Int(context.date.timeIntervalSince(since))))
                .font(BFFont.bodySmall.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
