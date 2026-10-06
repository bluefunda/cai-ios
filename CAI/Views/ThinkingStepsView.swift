import SwiftUI

/// The "Thought for Ns" card above an answer — claude.ai's thinking box. Collapsed, the header
/// is the latest thought (typing itself out while live) with a chevron. Expanded, a bordered box
/// lists "Thought for Ns" followed by each thought as a plain line; a line with more detail
/// expands on tap. Only steps that happened BEFORE the answer belong here — steps from mid-answer
/// render in place inside the answer (`InlineStepsGroupView`). Never fabricates steps.
struct ThinkingStepsView: View {
    let steps: [MessageStep]
    /// True while still thinking (ChatManager locks it at the first answer token).
    let isActive: Bool
    /// Persisted "Thought for Ns" duration, round-tripped through history/cache.
    let persistedDurationSeconds: Int?

    @State private var isExpanded = false
    @State private var expandedStepIds: Set<String> = []
    @State private var startedAt: Date?
    @State private var elapsedSeconds: Int?

    init(steps: [MessageStep], isActive: Bool, persistedDurationSeconds: Int? = nil, startedAt: Date? = nil) {
        self.steps = steps
        self.isActive = isActive
        self.persistedDurationSeconds = persistedDurationSeconds
        _startedAt = State(initialValue: startedAt)
        _elapsedSeconds = State(initialValue: persistedDurationSeconds)
    }

    private var durationText: String {
        elapsedSeconds.map { "Thought for \($0)s" } ?? "Thought"
    }

    private func headerRow() -> some View {
        Button {
            // Instant, not animated: this view lives in a List row, and an animated height change
            // overlapped the rows below while UIKit grew the cell. Only the chevron animates.
            isExpanded.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    if isActive {
                        TypingText(text: steps.last?.title ?? "Thinking…")
                    } else {
                        Text(steps.last?.title.nilIfEmpty ?? durationText)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                ThinkingChevron(isExpanded: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bfPointerHover()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._2) {
            headerRow()

            if isExpanded {
                VStack(alignment: .leading, spacing: BFSpacing._3) {
                    Text(isActive ? "Thinking…" : durationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(steps) { step in
                        thoughtRow(step)
                    }
                }
                .padding(BFSpacing._4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                )
            }
        }
        .onAppear { if startedAt == nil { startedAt = Date() } }
        // ChatManager's frozen duration is authoritative.
        .onChange(of: persistedDurationSeconds) { _, seconds in
            if let seconds { elapsedSeconds = seconds }
        }
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            if let persistedDurationSeconds {
                elapsedSeconds = persistedDurationSeconds
            } else if elapsedSeconds == nil, let startedAt {
                elapsedSeconds = MessageStep.thinkingDuration(since: startedAt)
            }
            isExpanded = false // claude.ai: open while live if opened, collapsed once done
        }
    }

    private func thoughtRow(_ step: MessageStep) -> some View {
        let isRowExpanded = expandedStepIds.contains(step.stepId)
        return Button {
            if step.hasExtraDetail { expandedStepIds.formSymmetricDifference([step.stepId]) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                TypingText(text: step.title, animates: step.isActive)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.75))
                    .multilineTextAlignment(.leading)
                if isRowExpanded {
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bfPointerHover()
    }
}

/// Steps that happened in the middle of an answer (text → tool → text), shown in place —
/// claude.ai's "Searched the web ⌄" group: a header summarising the group and, expanded, a
/// bordered box with one row per step ("Searched the web  <query>  ›", a reasoning line…).
/// Expanded while the group is still running, collapsed once its steps are done.
struct InlineStepsGroupView: View {
    let steps: [MessageStep]
    let isLive: Bool

    @State private var isExpanded: Bool
    @State private var expandedStepIds: Set<String> = []

    init(steps: [MessageStep], isLive: Bool) {
        self.steps = steps
        self.isLive = isLive
        _isExpanded = State(initialValue: isLive)
    }

    private var isRunning: Bool { isLive && steps.contains(where: \.isActive) }

    /// "Searched the web" / "Read fao.org" / "Read 3 pages", else the latest step.
    private var groupTitle: String {
        let parts = steps.compactMap(\.toolLabelAndValue)
        if parts.contains(where: { $0.label.hasPrefix("Search") }) {
            return isRunning ? "Searching the web" : "Searched the web"
        }
        let reads = parts.filter { $0.label.hasPrefix("Read") }
        if reads.count == 1 { return "\(isRunning ? "Reading" : "Read") \(reads[0].value)" }
        if reads.count > 1 { return "\(isRunning ? "Reading" : "Read") \(reads.count) pages" }
        return steps.last?.title ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._2) {
            Button { isExpanded.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if isRunning { ProgressView().controlSize(.mini) }
                    Text(groupTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ThinkingChevron(isExpanded: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .bfPointerHover()

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 { Divider() }
                        stepRow(step)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                )
            }
        }
        .onChange(of: isRunning) { _, running in
            if !running { isExpanded = false }
        }
    }

    private func stepRow(_ step: MessageStep) -> some View {
        let isRowExpanded = expandedStepIds.contains(step.stepId)
        return Button {
            if step.hasExtraDetail { expandedStepIds.formSymmetricDifference([step.stepId]) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let tool = step.toolLabelAndValue {
                        Text(tool.label).foregroundStyle(.secondary)
                        Text(tool.value).foregroundStyle(.primary).lineLimit(isRowExpanded ? nil : 1)
                    } else {
                        TypingText(text: step.title, animates: step.isActive)
                            .foregroundStyle(.secondary)
                            .lineLimit(isRowExpanded ? nil : 2)
                    }
                    if step.hasExtraDetail {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isRowExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.15), value: isRowExpanded)
                    }
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                if isRowExpanded {
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, BFSpacing._4)
            .padding(.vertical, BFSpacing._3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bfPointerHover()
    }
}

/// An answer with mid-answer steps rendered in place: the text is split at each step group's
/// position (`contentOffset`, UTF-16 units of the answer) and an `InlineStepsGroupView` drawn
/// there — text, "Searched the web ⌄", more text — like claude.ai. Without inline steps this is
/// exactly the plain paced answer.
struct AnswerWithInlineStepsView: View {
    let message: ChatMessage
    let isStreaming: Bool
    let wasStopped: Bool
    let onRevealingChanged: (Bool) -> Void

    /// Inline steps grouped by position, in order (steps at the same position share a group).
    private var groups: [(offset: Int, steps: [MessageStep])] {
        let inline = (message.steps ?? []).inlineSteps
        var result: [(offset: Int, steps: [MessageStep])] = []
        for step in inline.sorted(by: { ($0.contentOffset ?? 0) < ($1.contentOffset ?? 0) }) {
            let offset = step.contentOffset ?? 0
            if let last = result.last, last.offset == offset {
                result[result.count - 1].steps.append(step)
            } else {
                result.append((offset, [step]))
            }
        }
        return result
    }

    var body: some View {
        let groups = groups
        if groups.isEmpty {
            paced(id: message.id, text: message.content, live: true)
        } else {
            let units = Array(message.content.utf16)
            let bounds = groups.map { min(max(0, $0.offset), units.count) }
            VStack(alignment: .leading, spacing: BFSpacing._3) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    let start = index == 0 ? 0 : bounds[index - 1]
                    let segment = String(decoding: units[start..<bounds[index]], as: UTF16.self)
                    if !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        paced(id: "\(message.id)#\(index)", text: segment, live: false)
                    }
                    InlineStepsGroupView(steps: group.steps, isLive: isStreaming)
                }
                let tail = String(decoding: units[(bounds.last ?? 0)...], as: UTF16.self)
                if !tail.isEmpty {
                    // Keyed by group count: when a new group arrives mid-stream, the text so far
                    // becomes a finished segment above it and a fresh tail continues below.
                    paced(id: "\(message.id)#\(groups.count)", text: tail, live: true)
                }
            }
        }
    }

    private func paced(id: String, text: String, live: Bool) -> some View {
        PacedMarkdownView(
            messageId: id,
            targetContent: text,
            isStreaming: live && isStreaming && !text.isEmpty,
            wasStopped: live && wasStopped,
            onRevealingChanged: live ? onRevealingChanged : { _ in }
        )
        .font(BFFont.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

/// Shared disclosure chevron: points down when expanded, right when collapsed.
private struct ThinkingChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 0 : -90))
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

extension MessageStep {
    /// Whether the detail adds anything beyond the title (only then is a row expandable).
    var hasExtraDetail: Bool {
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return !detail.isEmpty && detail != title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A tool step's title split claude.ai-style into a dim label and the specific input:
    /// "Searched the web for \"wheat\"" → ("Searched the web", "wheat"); "Read fao.org" →
    /// ("Read", "fao.org"). nil for reasoning steps.
    var toolLabelAndValue: (label: String, value: String)? {
        for prefix in ["Searching the web for ", "Searched the web for "] where title.hasPrefix(prefix) {
            let query = String(title.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (String(prefix.dropLast(" for ".count)), query)
        }
        for prefix in ["Reading ", "Read "] where title.hasPrefix(prefix) {
            let host = String(title.dropFirst(prefix.count))
            if !host.contains(" ") { return (prefix.trimmingCharacters(in: .whitespaces), host) }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Text that types itself out as it grows — the live thought text reads as being written
/// (claude.ai) rather than jumping in whole sentences each time the router re-captions (~4x/s).
/// Growth that extends the shown text continues from where it is; a different text (a new
/// thought) types in from the start. Reveals any backlog within ~0.3s, so it never trails far
/// behind the live stream. `animates: false` (finished or history steps) renders instantly.
struct TypingText: View {
    let text: String
    var suffix: String = ""
    var animates: Bool = true

    @State private var shown: String?
    @State private var typingTask: Task<Void, Never>?

    private static let tick: Duration = .milliseconds(25)
    private static let ticksToCatchUp = 12

    var body: some View {
        Text((animates ? shown ?? "" : text) + suffix)
            .onChange(of: text, initial: true) { _, newText in type(toward: newText) }
            .onDisappear { typingTask?.cancel() }
    }

    private func type(toward target: String) {
        guard animates else { return }
        typingTask?.cancel()
        var current = shown ?? ""
        if !target.hasPrefix(current) { current = "" }
        shown = current
        typingTask = Task { @MainActor in
            while !Task.isCancelled, current.count < target.count {
                let step = max(1, (target.count - current.count) / Self.ticksToCatchUp)
                var end = target.index(target.startIndex, offsetBy: min(target.count, current.count + step))
                // Finish the word being revealed, so text appears word by word, not mid-word.
                if let space = target[end...].firstIndex(of: " "),
                   target.distance(from: end, to: space) <= 12 {
                    end = space
                }
                current = String(target[..<end])
                shown = current
                try? await Task.sleep(for: Self.tick)
            }
        }
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
