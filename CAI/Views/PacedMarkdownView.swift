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

    @State private var pacedContent: String = ""
    // Mirrors `targetContent` into @State so the long-running ticker task
    // below always reads the current value. `targetContent` is a `let` on a
    // value-type View struct — SwiftUI creates a fresh struct instance as
    // content streams in, but the ticker's `.task {}` (no `id:`, so it never
    // restarts) closed over whichever instance was live when it started, and
    // would otherwise loop forever comparing against that frozen value.
    // Equivalent to cai-android's `rememberUpdatedState(target)` in
    // MarkdownReveal.kt, solving the identical Compose-side pitfall.
    @State private var latestTarget: String = ""

    var body: some View {
        MarkdownView(content: pacedContent)
            .task(id: targetContent) {
                latestTarget = targetContent
                let trimmedTarget = targetContent.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedPaced = pacedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTarget.count < trimmedPaced.count || !trimmedTarget.hasPrefix(trimmedPaced) {
                    pacedContent = targetContent
                    PacedTextCache.shared.set(messageId, targetContent)
                }
            }
            .task {
                let charsPerSecond = 450.0
                var lastTick = Date()

                while !Task.isCancelled {
                    let currentTarget = latestTarget
                    if pacedContent.count < currentTarget.count {
                        let now = Date()
                        let elapsedSeconds = now.timeIntervalSince(lastTick)
                        lastTick = now
                        
                        let charsToReveal = max(1, min(60, Int(round(elapsedSeconds * charsPerSecond))))
                        let rawLength = min(currentTarget.count, pacedContent.count + charsToReveal)
                        
                        var targetLength = rawLength
                        if rawLength < currentTarget.count {
                            // Find next space or newline
                            let startIndex = currentTarget.index(currentTarget.startIndex, offsetBy: pacedContent.count)
                            let searchRange = startIndex..<currentTarget.endIndex
                            
                            var nextSpaceIdx: Int? = nil
                            var nextNewlineIdx: Int? = nil
                            
                            if let spaceRange = currentTarget.range(of: " ", range: searchRange) {
                                nextSpaceIdx = currentTarget.distance(from: currentTarget.startIndex, to: spaceRange.lowerBound)
                            }
                            if let newlineRange = currentTarget.range(of: "\n", range: searchRange) {
                                nextNewlineIdx = currentTarget.distance(from: currentTarget.startIndex, to: newlineRange.lowerBound)
                            }
                            
                            let boundary: Int?
                            switch (nextSpaceIdx, nextNewlineIdx) {
                            case (.some(let s), .some(let n)): boundary = min(s, n)
                            case (.some(let s), .none):        boundary = s
                            case (.none, .some(let n)):        boundary = n
                            case (.none, .none):               boundary = nil
                            }
                            
                            if let b = boundary, (b - pacedContent.count) <= (charsToReveal + 8) {
                                targetLength = min(currentTarget.count, b + 1)
                            }
                        }
                        
                        let nextIndex = currentTarget.index(currentTarget.startIndex, offsetBy: targetLength)
                        let nextPacedText = String(currentTarget[..<nextIndex])
                        pacedContent = nextPacedText
                        PacedTextCache.shared.set(messageId, nextPacedText)
                        
                        // Delay by 8 milliseconds
                        try? await Task.sleep(for: .milliseconds(8))
                    } else {
                        // Delay by 30 milliseconds before checking again
                        try? await Task.sleep(for: .milliseconds(30))
                        lastTick = Date()
                    }
                }
            }
            .onAppear {
                latestTarget = targetContent
                pacedContent = PacedTextCache.shared.get(messageId) ?? (isStreaming ? "" : targetContent)
            }
    }
}
