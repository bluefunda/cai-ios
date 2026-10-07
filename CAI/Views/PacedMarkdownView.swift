import SwiftUI

private final class PacedTextCache {
    static let shared = PacedTextCache()
    private var cache: [String: String] = [:]
    private var keys: [String] = []
    private let maxLimit = 50
    private let lock = NSLock()

    func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let val = cache[key] {
            // Move to end to maintain LRU
            if let idx = keys.firstIndex(of: key) {
                keys.remove(at: idx)
                keys.append(key)
            }
            return val
        }
        return nil
    }

    func set(_ key: String, _ value: String) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = value
        if let idx = keys.firstIndex(of: key) {
            keys.remove(at: idx)
        }
        keys.append(key)
        if keys.count > maxLimit {
            let oldest = keys.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}

struct PacedMarkdownView: View {
    let messageId: String
    let targetContent: String
    let isStreaming: Bool
    /// True when the user explicitly stopped this response.
    var wasStopped: Bool = false
    /// Reports whether this view is still actively revealing text, independent of isStreaming —
    /// which reflects the network finishing, not the local pace catching up to it. Lets the
    /// composer keep showing Stop for as long as text is still visibly printing.
    var onRevealingChanged: (Bool) -> Void = { _ in }

    @Environment(\.scenePhase) private var scenePhase
    @State private var pacedContent: String = ""
    // What's actually handed to MarkdownView — deliberately updated at a throttled rate, not
    // every reveal tick. MarkdownView's rendering (MarkdownParseCache's block parsing, and while
    // a code block is open, CodeBlockView's per-tick highlight materialization) costs O(current
    // content length) each time it runs — for a code block specifically, that's on top of the
    // parser itself re-scanning every accumulated line from the opening fence each tick, since an
    // unclosed code block is *always* the one open trailing block MarkdownParseCache can't avoid
    // re-parsing. That's cheap once, but paying it on every single 8ms tick doesn't scale — a
    // growing code block visibly printed slower than plain text as a result. Decoupling "advance
    // the text a little" (pacedContent, cheap, stays at full 8ms rate) from "re-render the
    // markdown" (renderedContent, throttled) fixes that without touching how characters are
    // indexed into anything — pure time-based gating on plain value types, so it doesn't share
    // any risk with the String.Index-across-ticks bug that caused the earlier crash here.
    @State private var renderedContent: String = ""
    @State private var lastRenderPublish = ContinuousClock.now
    @State private var latestTarget: String = ""
    @State private var revealTask: Task<Void, Never>?
    // Drives MarkdownView's trailing opacity fade — matches cai-android's `isPacingActive`
    // (network streaming OR the local reveal hasn't caught up yet), not raw network isStreaming.
    @State private var isActivelyRevealing = false
    // Sticky, independent of the `wasStopped` prop: ChatView.swift only sets that true for
    // whichever message is currently *last* in the conversation, so it flips back to false for
    // this same, still-mounted message the instant the user sends another prompt (a new message
    // becomes last). Relying on the prop alone meant a message that was ever stopped could later
    // un-freeze — if any further update reached it after that prop flipped back (e.g. content
    // that trickled in during a stop that needed several taps to actually register server-side,
    // updating `latestTarget` past `pacedContent` while still nominally "frozen"), the guard
    // below would no longer block it, and it would resume/replay the tail that arrived during
    // that window. Once true this never resets for the lifetime of this view instance.
    @State private var hasFrozen = false
    // Smoothed chars/sec at which streamed text is arriving — see maxLagSeconds.
    @State private var arrivalRate: Double = 0
    @State private var lastArrival: ContinuousClock.Instant?

    init(
        messageId: String,
        targetContent: String,
        isStreaming: Bool,
        wasStopped: Bool = false,
        onRevealingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.messageId = messageId
        self.targetContent = targetContent
        self.isStreaming = isStreaming
        self.wasStopped = wasStopped
        self.onRevealingChanged = onRevealingChanged
        // A message that isn't streaming has nothing to reveal — start with its full text so
        // the List row's FIRST layout pass already measures the real height. Starting from ""
        // and filling it in onChange(initial:) one update later made every history row size
        // as empty first, then grow: the List re-measured those cells a beat late, and the
        // text drew over the rows below for a moment (the overlap seen when switching chats).
        if !isStreaming {
            _pacedContent = State(initialValue: targetContent)
            _renderedContent = State(initialValue: targetContent)
            _latestTarget = State(initialValue: targetContent)
        }
    }

    // A word-stepped reveal (fixed pause between whole words, matching the Gemini app's look)
    // was tried here and explicitly rejected: any discrete step with a real pause between
    // updates reads as a stutter, no matter how nicely each step fades in. Back to continuous:
    // ported from cai-android's MarkdownReveal.kt — characters are revealed at a continuous rate
    // computed from *actual measured elapsed time* since the last tick, rather than a fixed chunk
    // every fixed interval. What actually determines whether this reads as "smooth" vs "word by
    // word" is keeping the *tick interval* small (paceDelay) so each individual update is only a
    // couple of characters — well under one word — regardless of the overall chars/sec rate.
    private static let paceDelay: Duration = .milliseconds(8)
    // Adaptive rate (was a fixed 460 chars/s): aim to drain whatever has arrived but isn't shown
    // yet within `catchUpSeconds`. A fast model (e.g. Groq) builds a big backlog, so the reveal
    // speeds up instead of trailing seconds behind a finished stream; a slow model leaves a small
    // backlog, so the reveal slows down and spreads each bursty network chunk across the gap to
    // the next one instead of racing ahead and stalling (stop-and-go). Clamped both ways so it
    // never crawls or dumps a wall of text in one tick.
    private static let catchUpSeconds: Double = 0.6
    private static let minCharsPerSecond: Double = 90
    private static let maxCharsPerSecond: Double = 2400
    // Pace to the stream's measured ARRIVAL rate (smoothed), not just "drain the backlog in
    // 0.6s". A provider that sends few, large chunks (Gemini: hundreds of chars ~once a second)
    // otherwise revealed each chunk in a 0.6s burst and then sat idle until the next — fast and
    // stop-and-go. Matching the arrival rate spreads each chunk across the gap to the next one.
    // `maxLagSeconds` still bounds how far the reveal may trail what has arrived.
    private static let maxLagSeconds: Double = 1.5
    private static let arrivalSmoothing: Double = 0.15
    private static let maxCharsPerTick = 60
    private static let boundarySnapSlack = 8
    // How often the markdown re-render may run while revealing. Plain text is cheap enough to
    // redraw ~every frame (was 60ms for everything, i.e. ~16 visible updates/s, each dropping
    // several words at once); an OPEN code block keeps the slower interval, because re-parsing and
    // re-highlighting a growing fenced block costs O(block length) per render.
    private static let renderInterval: Duration = .milliseconds(16)
    private static let codeBlockRenderInterval: Duration = .milliseconds(60)

    /// True when `text` ends inside an unclosed ``` fence — an odd number of fences so far.
    private static func endsInsideCodeBlock(_ text: String) -> Bool {
        var count = 0
        var searchStart = text.startIndex
        while let range = text.range(of: "```", range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count % 2 == 1
    }

    var body: some View {
        MarkdownView(
            content: isActivelyRevealing
                ? StreamingMarkdown.displayable(renderedContent, insideCodeBlock: Self.endsInsideCodeBlock(renderedContent))
                : renderedContent,
            isStreaming: isActivelyRevealing,
            cacheKey: messageId
        )
            .onChange(of: targetContent, initial: true) { _, newTarget in
                recordArrival(newTarget)
                latestTarget = newTarget

                if pacedContent.isEmpty {
                    if isStreaming {
                        let cached = PacedTextCache.shared.get(messageId) ?? ""
                        pacedContent = cached
                        renderedContent = cached
                    } else {
                        // A fresh (re)appearance of a message that isn't currently streaming —
                        // e.g. scrolled far enough off-screen that SwiftUI tore down and
                        // recreated this view, resetting pacedContent to "". Whether this
                        // message finished naturally or was stopped, there's nothing to
                        // animate: snap straight to the final text. This must happen before the
                        // divergence check below and regardless of wasStopped/cache state —
                        // "" is trivially a prefix of any string, so falling through with
                        // pacedContent still empty would pass that check and kick off a full
                        // from-scratch typewriter replay of an already-completed response. This
                        // was most visible after tapping Stop early enough that no reveal tick
                        // (and so no PacedTextCache entry) had happened yet for this message.
                        publish(newTarget)
                        return
                    }
                }

                // Once the user has stopped this still-mounted message, it must stay frozen no
                // matter what — a cancelled network task is cooperative, not immediate, so a
                // chunk or two already in flight when Stop was tapped can still land here
                // afterward. Without this guard, that late arrival would unconditionally
                // restart the reveal task below, silently resuming a printing effect the user
                // explicitly stopped — sometimes surviving several taps of Stop in a row.
                // Checks the sticky hasFrozen flag too, not just the wasStopped prop — see its
                // declaration for why the prop alone isn't enough.
                guard !wasStopped, !hasFrozen else { return }

                // Only a genuine divergence (the target no longer starts with what's already
                // paced out — e.g. a retried/corrected message) should jump straight to the new
                // text. Comparing *trimmed* strings for this was fragile: trailing whitespace
                // shifts constantly as more tokens arrive, so trimmedTarget could stop having
                // trimmedPaced as a prefix on an ordinary append, snapping pacedContent all the
                // way to the current target and reading as "several lines landing at once."
                // Comparing the untrimmed strings directly has no such false positives — a
                // shorter newTarget already fails hasPrefix on its own, no separate length check
                // needed.
                if !newTarget.hasPrefix(pacedContent) {
                    publish(newTarget)
                }
                startRevealIfNeeded()
            }
            .onChange(of: wasStopped) { _, stopped in
                guard stopped else { return }
                // Freeze exactly where the reveal currently is — matches cai-android's "a
                // cancelled stream just freezes wherever the ticker last painted" — rather than
                // jumping to every character that had already arrived over the wire, which
                // showed as several lines landing at once right when Stop was tapped. Sticky:
                // never cleared again for the lifetime of this view instance, so this message
                // stays frozen even after `wasStopped` itself later flips back to false.
                hasFrozen = true
                revealTask?.cancel()
                revealTask = nil
                setRevealing(false)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !wasStopped, !hasFrozen else { return }
                snapToEnd()
            }
            .onDisappear {
                revealTask?.cancel()
                revealTask = nil
                setRevealing(false)
            }
    }

    private func setRevealing(_ value: Bool) {
        isActivelyRevealing = value
        onRevealingChanged(value)
    }

    /// Immediately syncs pacedContent, renderedContent, and the cache to the same value — for
    /// every "snap straight to this text" path (fresh mount, divergence, stop, resume). The
    /// throttled render path inside the tick loop below is the only place these two are
    /// deliberately allowed to drift apart.
    /// Updates the smoothed arrival rate from how much text arrived since the previous update.
    private func recordArrival(_ newTarget: String) {
        let now = ContinuousClock.now
        defer { lastArrival = now }
        guard isStreaming, let last = lastArrival else { return }
        let added = newTarget.count - latestTarget.count
        guard added > 0 else { return }
        let components = (now - last).components
        let seconds = max(Double(components.seconds) + Double(components.attoseconds) * 1e-18, 0.05)
        let instant = Double(added) / seconds
        arrivalRate = arrivalRate == 0 ? instant : arrivalRate + Self.arrivalSmoothing * (instant - arrivalRate)
    }

    private func publish(_ value: String) {
        pacedContent = value
        renderedContent = value
        PacedTextCache.shared.set(messageId, value)
    }

    private func startRevealIfNeeded() {
        guard revealTask == nil, pacedContent.count < latestTarget.count else { return }
        setRevealing(true)
        revealTask = Task { @MainActor in
            var lastTick = ContinuousClock.now
            while !Task.isCancelled {
                let target = latestTarget
                guard pacedContent.count < target.count else { break }
                guard target.hasPrefix(pacedContent) else {
                    publish(target)
                    break
                }

                try? await Task.sleep(for: Self.paceDelay)
                let now = ContinuousClock.now
                let elapsed = now - lastTick
                lastTick = now
                let components = elapsed.components
                let elapsedSeconds = Double(components.seconds) + Double(components.attoseconds) * 1e-18

                // Characters to reveal this tick are derived from *actually measured* elapsed
                // time, not assumed from paceDelay — if a tick lands late (scheduler jitter,
                // markdown re-parse cost, scroll contention), the next one reveals proportionally
                // more so the average rate holds steady instead of visibly stalling.
                let backlog = Double(target.count - pacedContent.count)
                // The arrival rate, sped up only if the reveal would trail by more than
                // maxLagSeconds. With no rate measured yet, drain over catchUpSeconds.
                // Also after the stream ends: keep the measured pace and finish within maxLagSeconds,
                // instead of rushing the remainder out in catchUpSeconds (a visible end burst).
                let desiredRate = arrivalRate > 0
                    ? max(arrivalRate, backlog / Self.maxLagSeconds)
                    : backlog / Self.catchUpSeconds
                let charsPerSecond = min(max(desiredRate, Self.minCharsPerSecond), Self.maxCharsPerSecond)
                let rawChars = Int((elapsedSeconds * charsPerSecond).rounded())
                let charsToReveal = min(max(rawChars, 1), Self.maxCharsPerTick)

                // Recomputed fresh against *this* tick's `target` every time — a String.Index
                // cached from a previous tick is not safe to reuse here. `target` is re-read from
                // latestTarget every iteration, and once new content has arrived it's a genuinely
                // different String instance — even though target.hasPrefix(pacedContent) confirms
                // the prefix *bytes* are identical, Swift's small-string vs. large-string internal
                // representations encode String.Index differently, so an index computed against
                // one instance is not guaranteed valid for another. An earlier version of this
                // code cached the index across ticks to avoid this O(position) walk every time —
                // confirmed unsafe by an actual crash (EXC_BAD_INSTRUCTION in this subscript, from
                // exactly that pattern), not just a theoretical risk, so it's gone.
                let startIndex = target.index(target.startIndex, offsetBy: pacedContent.count)

                let rawLength = min(target.count, pacedContent.count + charsToReveal)
                var endIndex = target.index(startIndex, offsetBy: rawLength - pacedContent.count)
                if rawLength < target.count {
                    let spaceRange = target.range(of: " ", range: endIndex..<target.endIndex)
                    let newlineRange = target.range(of: "\n", range: endIndex..<target.endIndex)
                    let boundary: String.Index?
                    switch (spaceRange, newlineRange) {
                    case (nil, nil): boundary = nil
                    case (let space?, nil): boundary = space.lowerBound
                    case (nil, let newline?): boundary = newline.lowerBound
                    case (let space?, let newline?): boundary = min(space.lowerBound, newline.lowerBound)
                    }
                    if let boundary,
                       target.distance(from: endIndex, to: boundary) <= charsToReveal + Self.boundarySnapSlack {
                        endIndex = target.index(after: boundary)
                    }
                }

                // Append just the new delta onto the existing buffer (amortized O(delta), like a
                // growable array) instead of materializing the whole revealed-so-far prefix as a
                // brand-new String every tick (O(current length) per tick, however it's indexed).
                pacedContent.append(contentsOf: target[startIndex..<endIndex])
                PacedTextCache.shared.set(messageId, pacedContent)

                // renderedContent (what MarkdownView actually draws) only updates at
                // renderInterval, not every paceDelay tick — see its declaration for why. Always
                // publish on the tick that catches pacedContent up to the target, though, so the
                // response doesn't sit briefly stale right when it finishes.
                let sinceLastRender = now - lastRenderPublish
                let interval = sinceLastRender >= Self.codeBlockRenderInterval
                    ? Self.renderInterval // already overdue for either case — skip the fence scan
                    : (Self.endsInsideCodeBlock(pacedContent) ? Self.codeBlockRenderInterval : Self.renderInterval)
                if sinceLastRender >= interval || pacedContent.count >= target.count {
                    renderedContent = pacedContent
                    lastRenderPublish = now
                }
            }
            // Guarantees renderedContent is fully caught up even if the loop broke (cancellation,
            // divergence-publish above) before its own throttled-publish check could run.
            renderedContent = pacedContent
            revealTask = nil
            setRevealing(false)
        }
    }

    private func snapToEnd() {
        let wasRevealing = revealTask != nil
        revealTask?.cancel()
        revealTask = nil
        publish(latestTarget)
        if wasRevealing { setRevealing(false) }
    }
}

/// Display-only cleanup for markdown that is still being revealed (claude.ai-style: elements
/// appear once they can render, never as half-typed syntax). The revealed prefix often ends
/// mid-construct — a lone "##", a "- " with no text, an unclosed "**", a table row still being
/// typed — which rendered as raw symbols for a moment and then visibly reflowed into the real
/// element ("formatting jumps"). This holds such a tail back (or closes it) until it completes.
/// Never applied to finished text, and never inside an open code fence (code is shown verbatim).
enum StreamingMarkdown {
    /// Line prefixes that mean nothing yet on their own: a heading/list/quote marker with no text,
    /// a fence opener still getting its language, a rule/setext underline, a table row in progress.
    private static let incompleteLinePattern = try? NSRegularExpression(
        pattern: #"^\s*(#{1,6}\s*|[-*+]\s*|\d+[.)]\s*|>\s*|`{1,3}[\w+-]*|[-=_*]{1,}\s*|\|.*)$"#
    )

    static func displayable(_ text: String, insideCodeBlock: Bool) -> String {
        guard !text.isEmpty, !insideCodeBlock else { return text }
        // A display formula ($$…$$) still being typed: hide it until its closing $$ arrives, so
        // it appears once, formatted, instead of as raw "$$3.22B = 1" for a moment.
        let mathFences = text.components(separatedBy: "$$").count - 1
        if mathFences % 2 == 1, let open = text.range(of: "$$", options: .backwards) {
            return displayable(String(text[..<open.lowerBound]), insideCodeBlock: false)
        }
        var body = text
        var lastLine = ""
        if let newline = text.lastIndex(of: "\n") {
            body = String(text[...newline])
            lastLine = String(text[text.index(after: newline)...])
        } else {
            body = ""
            lastLine = text
        }

        // 1. A trailing line that is only a block marker (or a half-typed table row) is held
        //    back until its line completes.
        let range = NSRange(lastLine.startIndex..., in: lastLine)
        if incompleteLinePattern?.firstMatch(in: lastLine, range: range) != nil {
            return body
        }

        // 2. Inline constructs still open in the trailing line are closed or trimmed.
        return body + closeInline(lastLine)
    }

    private static func closeInline(_ line: String) -> String {
        var line = line
        // A half-typed link: hide from its "[" until the whole "[text](url)" has arrived.
        if let open = line.lastIndex(of: "["), !line[open...].contains(")") {
            line = String(line[..<open])
        }
        // An opening "**" with nothing after it yet, or a lone trailing "*"/"_" (emphasis
        // still forming), is hidden until its text arrives.
        if line.hasSuffix("**"), line.components(separatedBy: "**").count % 2 == 0 {
            line.removeLast(2)
        } else if let last = line.last, last == "*" || last == "_", !line.hasSuffix("**") {
            line.removeLast()
        }
        // Unclosed bold / inline code: close them so the text renders styled while it types.
        if line.components(separatedBy: "**").count % 2 == 0 { line += "**" }
        let ticks = line.replacingOccurrences(of: "```", with: "").filter { $0 == "`" }.count
        if ticks % 2 == 1 { line += "`" }
        return line
    }
}
