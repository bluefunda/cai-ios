import SwiftUI

// MARK: - Requests Type
// The Requests space's small type scale, all from BFFont's Mac-scaled sidebar sizes so
// rows match the sidebar's density on every platform (P13: no display face here;
// numbers, counts and dates use monospaced digits so columns line up).

enum RQFont {
    static var number: Font { BFFont.sidebarMeta.weight(.semibold).monospacedDigit() }
    static var rowTitle: Font { BFFont.sidebarItem.weight(.semibold) }
    static var meta: Font { BFFont.sidebarMeta }
    static var body: Font { BFFont.sidebarItem }
    static var label: Font { BFFont.sidebarSection }
    static var pill: Font { .system(size: 11, weight: .semibold) }
}

// MARK: - Status Pill

/// Capsule, 11 pt semibold, sentence case — colour from `ChangeRequestStatus.style`,
/// the one place status becomes colour (P13). Always carries its label.
struct StatusPill: View {
    let status: ChangeRequestStatus

    var body: some View {
        let style = status.style
        Text(style.label)
            .font(RQFont.pill)
            .foregroundStyle(style.text)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.fill, in: Capsule())
            .fixedSize()
            .accessibilityLabel("Status: \(style.label)")
    }
}

// MARK: - Priority

/// severityData.type is free text on the wire ("Low"/"Medium"/"High"), matched by name.
/// Quiet on purpose: a coloured glyph plus the word, so it never competes with status.
struct PriorityPill: View {
    let text: String

    private var color: Color {
        switch text.lowercased() {
        case "high", "critical": return BFColor.happyRed
        case "medium": return BFColor.happyOrange
        default: return Color.secondary
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flag.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Priority: \(text)")
    }
}

// MARK: - Owner Badge

/// requestedBy: avatar, plus the name when there's room for it.
struct OwnerBadge: View {
    let name: String?
    let avatarURLString: String?
    var showsName = true

    var body: some View {
        HStack(spacing: 4) {
            RQAvatar(urlString: avatarURLString, size: 18)
            if showsName, let name, !name.isBlank {
                Text(name)
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name.map { "Requested by \($0)" } ?? "Requester unknown")
    }
}

struct RQAvatar: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(Color.secondary.opacity(0.45))
    }
}

// MARK: - Stage Rail
// The Requests space's one bold element (P13): a change request's journey — `stage` of
// `totalStages`, typically DEV → QAS → PRD — as a row of short connected segments.
// Completed segments are Deep Blue, the current one takes its status colour, future
// ones are hairline. Full size in the detail header, mini (48 × 4 pt) in list rows.
// No stage data → draws nothing, never a placeholder rail.

struct StageRail: View {
    enum Size { case mini, full }

    let stage: Int?
    let totalStages: Int?
    let status: ChangeRequestStatus
    var stageStatus: String?
    var size: Size = .mini

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Clamped so a backend sending stage 0 or stage > total still draws sensibly.
    static func segments(stage: Int?, totalStages: Int?) -> (current: Int, total: Int)? {
        guard let stage, let totalStages, totalStages > 0 else { return nil }
        return (min(max(stage, 1), totalStages), totalStages)
    }

    var body: some View {
        if let segments = Self.segments(stage: stage, totalStages: totalStages) {
            switch size {
            case .mini:
                bar(segments, height: 4, spacing: 2)
                    .frame(width: 48)
                    .accessibilityElement()
                    .accessibilityLabel("Stage \(segments.current) of \(segments.total)")
            case .full:
                VStack(alignment: .leading, spacing: 6) {
                    bar(segments, height: 6, spacing: 3)
                    HStack(spacing: 6) {
                        Text("Stage \(segments.current) of \(segments.total)")
                            .font(RQFont.meta.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(BFColor.secondaryAdaptive)
                        if let stageStatus, !stageStatus.isBlank {
                            Text(stageStatus)
                                .font(RQFont.meta)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func bar(_ segments: (current: Int, total: Int), height: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(1...segments.total, id: \.self) { index in
                Capsule()
                    .fill(color(for: index, current: segments.current))
                    .frame(height: height)
            }
        }
        // Animates only when the stage itself changes (e.g. after a status change the
        // user made succeeds) — never on first appearance.
        .animation(reduceMotion ? nil : .easeOut(duration: BFMotion.slow), value: segments.current)
    }

    private func color(for index: Int, current: Int) -> Color {
        if index < current { return BFColor.secondaryAdaptive }
        if index == current { return status.style.mark }
        return BFColor.hairline
    }
}

// MARK: - Error Card
// P11: a Requests failure is space-scoped and recoverable — an inline card with Retry,
// never an alert that ends in a dead end, never a sign-out.

struct RequestsErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(BFColor.happyOrange)
            Text(message)
                .font(RQFont.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .tint(BFColor.primary)
                .bfPointerHover()
                .accessibilityIdentifier("requests.retry")
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(BFColor.surfaceRaised, in: RoundedRectangle(cornerRadius: BFRadius.xl2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BFRadius.xl2, style: .continuous)
                .strokeBorder(BFColor.hairline, lineWidth: 0.5)
        )
        .padding(BFSpacing._4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The user-facing line for a load failure: what happened and what to do next
    /// (P13 copy — errors never apologise).
    static func message(for error: String?, subject: String) -> String {
        guard let error, !error.isBlank else {
            return "Couldn't load \(subject). Check your connection and try again."
        }
        return error
    }
}

// MARK: - Section Label

/// Small, sentence case, secondary — field labels in the detail screen.
struct RQFieldLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(RQFont.meta)
            .foregroundStyle(.secondary)
    }
}
