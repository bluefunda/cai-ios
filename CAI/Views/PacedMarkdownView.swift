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

    // A word-stepped reveal (fixed pause between whole words, matching the Gemini app's look)
    // was tried here and explicitly rejected: any discrete step with a real pause between
    // updates reads as a stutter, no matter how nicely each step fades in. Back to continuous:
    // ported from cai-android's MarkdownReveal.kt — characters are revealed at a continuous rate
    // computed from *actual measured elapsed time* since the last tick, rather than a fixed chunk
    // every fixed interval. What actually determines whether this reads as "smooth" vs "word by
    // word" is keeping the *tick interval* small (paceDelay) so each individual update is only a
    // couple of characters — well under one word — regardless of the overall chars/sec rate.
    private static let paceDelay: Duration = .milliseconds(8)
    private static let charsPerSecond: Double = 460
    private static let maxCharsPerTick = 60
    private static let boundarySnapSlack = 8
    // How often the (expensive) markdown re-render is allowed to run while actively revealing —
    // independent of paceDelay, which stays fast so the underlying text keeps advancing smoothly.
    private static let renderInterval: Duration = .milliseconds(60)

    var body: some View {
        MarkdownView(content: renderedContent, isStreaming: isActivelyRevealing, cacheKey: messageId)
            .onChange(of: targetContent, initial: true) { _, newTarget in
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
                let rawChars = Int((elapsedSeconds * Self.charsPerSecond).rounded())
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
                if sinceLastRender >= Self.renderInterval || pacedContent.count >= target.count {
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
