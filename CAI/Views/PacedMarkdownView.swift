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
    @State private var latestTarget: String = ""
    @State private var revealTask: Task<Void, Never>?
    // Drives MarkdownView's trailing opacity fade — matches cai-android's `isPacingActive`
    // (network streaming OR the local reveal hasn't caught up yet), not raw network isStreaming.
    @State private var isActivelyRevealing = false

    // A word-stepped reveal (fixed pause between whole words, matching the Gemini app's look)
    // was tried here and explicitly rejected: any discrete step with a real pause between
    // updates reads as a stutter, no matter how nicely each step fades in. Back to continuous:
    // ported from cai-android's MarkdownReveal.kt — characters are revealed at a continuous rate
    // computed from *actual measured elapsed time* since the last tick, rather than a fixed chunk
    // every fixed interval. What actually determines whether this reads as "smooth" vs "word by
    // word" is keeping the *tick interval* small (paceDelay) so each individual update is only a
    // couple of characters — well under one word — regardless of the overall chars/sec rate.
    private static let paceDelay: Duration = .milliseconds(8)
    private static let charsPerSecond: Double = 300
    private static let maxCharsPerTick = 60
    private static let boundarySnapSlack = 8

    var body: some View {
        MarkdownView(content: pacedContent, isStreaming: isActivelyRevealing, cacheKey: messageId)
            .onChange(of: targetContent, initial: true) { _, newTarget in
                latestTarget = newTarget
                // Once the user has stopped this message, it must stay frozen no matter what
                // — a cancelled network task is cooperative, not immediate, so a chunk or two
                // already in flight when Stop was tapped can still land here afterward. Without
                // this guard, that late arrival would unconditionally restart the reveal task
                // below, silently resuming a printing effect the user explicitly stopped —
                // sometimes surviving several taps of Stop in a row.
                guard !wasStopped else { return }
                if pacedContent.isEmpty {
                    pacedContent = PacedTextCache.shared.get(messageId) ?? ""
                }
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
                    pacedContent = newTarget
                    PacedTextCache.shared.set(messageId, newTarget)
                }
                startRevealIfNeeded()
            }
            .onChange(of: wasStopped) { _, stopped in
                guard stopped else { return }
                // Freeze exactly where the reveal currently is — matches cai-android's "a
                // cancelled stream just freezes wherever the ticker last painted" — rather than
                // jumping to every character that had already arrived over the wire, which
                // showed as several lines landing at once right when Stop was tapped.
                revealTask?.cancel()
                revealTask = nil
                setRevealing(false)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !wasStopped else { return }
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

    private func startRevealIfNeeded() {
        guard revealTask == nil, pacedContent.count < latestTarget.count else { return }
        setRevealing(true)
        revealTask = Task { @MainActor in
            var lastTick = ContinuousClock.now
            while !Task.isCancelled {
                let target = latestTarget
                guard pacedContent.count < target.count else { break }
                guard target.hasPrefix(pacedContent) else {
                    pacedContent = target
                    PacedTextCache.shared.set(messageId, target)
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

                let rawLength = min(target.count, pacedContent.count + charsToReveal)
                var targetLength = rawLength
                if rawLength < target.count {
                    let searchStart = target.index(target.startIndex, offsetBy: rawLength)
                    let spaceRange = target.range(of: " ", range: searchStart..<target.endIndex)
                    let newlineRange = target.range(of: "\n", range: searchStart..<target.endIndex)
                    let boundary: String.Index?
                    switch (spaceRange, newlineRange) {
                    case (nil, nil): boundary = nil
                    case (let space?, nil): boundary = space.lowerBound
                    case (nil, let newline?): boundary = newline.lowerBound
                    case (let space?, let newline?): boundary = min(space.lowerBound, newline.lowerBound)
                    }
                    if let boundary,
                       target.distance(from: searchStart, to: boundary) <= charsToReveal + Self.boundarySnapSlack {
                        targetLength = min(target.count, target.distance(from: target.startIndex, to: boundary) + 1)
                    }
                }

                let nextIndex = target.index(target.startIndex, offsetBy: targetLength)
                let nextPaced = String(target[..<nextIndex])
                pacedContent = nextPaced
                PacedTextCache.shared.set(messageId, nextPaced)
            }
            revealTask = nil
            setRevealing(false)
        }
    }

    private func snapToEnd() {
        let wasRevealing = revealTask != nil
        revealTask?.cancel()
        revealTask = nil
        pacedContent = latestTarget
        PacedTextCache.shared.set(messageId, latestTarget)
        if wasRevealing { setRevealing(false) }
    }
}
