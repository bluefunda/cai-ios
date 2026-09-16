import SwiftUI

/// Live tool-use status, shown above the answer while (and after) a response
/// streams — bluefunda/cai-ios#310. Mirrors claude.ai's collapsible
/// "Thought for Ns" box: one row per real backend `stream_status` step
/// (bluefunda/cai-llm-router#324), the currently-active step expanded with a
/// highlighted border, prior steps collapsed to their title. Never fabricates
/// steps — only renders when `message.steps` is non-empty, i.e. only for
/// turns where the backend actually ran a tool.
struct ThinkingStepsView: View {
    let steps: [MessageStep]
    /// True while the owning message is still streaming — drives the "Thinking…"
    /// vs. "Thought for Ns" header text.
    let isActive: Bool
    /// Persisted "Thought for Ns" duration (bluefunda/cai-ios#310 follow-up),
    /// computed once by `ChatManager` and round-tripped through history/cache.
    /// Used as the initial value so a reloaded, already-done message shows a
    /// real duration immediately, instead of only being derivable by this
    /// view having been live for the whole stream.
    let persistedDurationSeconds: Int?

    @State private var isExpanded: Bool
    @State private var expandedStepIds: Set<String> = []
    @State private var startedAt: Date?
    @State private var elapsedSeconds: Int?

    init(steps: [MessageStep], isActive: Bool, persistedDurationSeconds: Int? = nil) {
        self.steps = steps
        self.isActive = isActive
        self.persistedDurationSeconds = persistedDurationSeconds
        // Always collapsed by default — matches claude.ai, which shows only the
        // single-line running caption (plus timer) in the header while streaming
        // and never auto-opens the full step list, even while still active. The
        // user taps the header to see the accumulated sub-sections; the box
        // otherwise stays compact instead of growing taller as more steps arrive.
        _isExpanded = State(initialValue: false)
        _elapsedSeconds = State(initialValue: persistedDurationSeconds)
    }

    // While active, the header IS the current step's live caption (plus a
    // running seconds count) — matching claude.ai, which has no separate
    // generic "Thinking…" wrapper distinct from the current row. Once done,
    // it keeps the "Thought for Ns" summary but ALSO keeps the last caption
    // alongside it (e.g. "Thought for 48s  Deriving the error term's exact
    // decay rate and sign pattern."), not just the bare summary alone.
    private func headerText(liveElapsed: Int?) -> String {
        if isActive {
            let caption = steps.last?.title ?? "Thinking…"
            if let liveElapsed { return "\(caption)  \(liveElapsed)s" }
            return caption
        }
        let summary = elapsedSeconds.map { "Thought for \($0)s" } ?? "Thought"
        if let lastCaption = steps.last?.title, !lastCaption.isEmpty {
            return "\(summary)  \(lastCaption)"
        }
        return summary
    }

    private func headerRow(liveElapsed: Int?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(headerText(liveElapsed: liveElapsed))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bfPointerHover()
        .padding(.bottom, isExpanded ? BFSpacing._2 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isActive {
                TimelineView(.periodic(from: startedAt ?? Date(), by: 1)) { context in
                    headerRow(liveElapsed: startedAt.map { max(0, Int(context.date.timeIntervalSince($0))) })
                }
            } else {
                headerRow(liveElapsed: nil)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(step, isFirst: index == 0, isLast: index == steps.count - 1)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous)
                        .strokeBorder(BFColor.neutral200, lineWidth: 1)
                )
            }
        }
        .onAppear { if startedAt == nil { startedAt = Date() } }
        .onChange(of: isActive) { _, active in
            if !active {
                if elapsedSeconds == nil, let startedAt {
                    elapsedSeconds = max(1, Int(Date().timeIntervalSince(startedAt).rounded()))
                }
                // Auto-collapse once the message finishes — matches claude.ai,
                // which shows the box open while live, then collapsed once done.
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
            }
        }
    }

    @ViewBuilder
    private func stepRow(_ step: MessageStep, isFirst: Bool, isLast: Bool) -> some View {
        // Collapsed by default for every row, active or not — the user can toggle
        // any row, including the one currently streaming, matching claude.ai
        // (no row is locked open just because it's in progress).
        let isRowExpanded = expandedStepIds.contains(step.stepId)
        // For a short reasoning paragraph, the derived caption IS the whole
        // segment — title and detail end up identical, and there's nothing
        // extra worth expanding to see. Only offer the expand affordance when
        // detail actually adds something beyond the title.
        let hasExtraDetail = !step.detail.isEmpty
            && step.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            != step.title.trimmingCharacters(in: .whitespacesAndNewlines)

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if expandedStepIds.contains(step.stepId) {
                    expandedStepIds.remove(step.stepId)
                } else {
                    expandedStepIds.insert(step.stepId)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if step.isActive {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(step.title)
                        .font(.subheadline)
                        .foregroundStyle(step.isActive ? BFColor.primary : .secondary)
                        .lineLimit(isRowExpanded ? nil : 1)
                    Spacer(minLength: 0)
                    if hasExtraDetail {
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isRowExpanded ? 0 : -90))
                    }
                }

                if isRowExpanded, hasExtraDetail {
                    // Dimmed further than plain .secondary — reasoning text should
                    // read as clearly distinct from (and less prominent than) the
                    // actual answer content below it.
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(BFColor.neutral600)
                        .padding(.leading, 22)
                }
            }
            .padding(.horizontal, BFSpacing._3)
            .padding(.vertical, BFSpacing._2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bfPointerHover()
        .background(
            step.isActive
                ? RoundedRectangle(cornerRadius: BFRadius.lg, style: .continuous)
                    .strokeBorder(BFColor.primary, lineWidth: 1)
                    .padding(3)
                : nil
        )
    }
}

#Preview {
    VStack {
        ThinkingStepsView(
            steps: [
                MessageStep(stepId: "1", title: "Searched the knowledge base", detail: "Found 3 relevant results.", isActive: false),
                MessageStep(stepId: "2", title: "Reading a file", detail: "Reviewing uploaded_report.pdf for context.", isActive: true),
            ],
            isActive: true
        )
    }
    .padding()
}
