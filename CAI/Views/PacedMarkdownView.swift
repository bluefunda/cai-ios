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
    // Mirrors `targetContent` into @State so the ticker callback
    // always reads the current value. `targetContent` is a `let` on a
    // value-type View struct — SwiftUI creates a fresh struct instance as
    // content streams in, but the ticker closed over whichever instance
    // was live when it started.
    @State private var latestTarget: String = ""

    @StateObject private var ticker = FrameTicker()

    var body: some View {
        MarkdownView(content: pacedContent)
            .onChange(of: targetContent, initial: true) { _, newTarget in
                latestTarget = newTarget
                if pacedContent.isEmpty {
                    pacedContent = PacedTextCache.shared.get(messageId) ?? (isStreaming ? "" : newTarget)
                }
                let trimmedTarget = newTarget.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedPaced = pacedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTarget.count < trimmedPaced.count || !trimmedTarget.hasPrefix(trimmedPaced) {
                    pacedContent = newTarget
                    PacedTextCache.shared.set(messageId, newTarget)
                }

                if pacedContent.count < newTarget.count {
                    ticker.start { elapsed in
                        advancePacing(elapsed: elapsed)
                    }
                }
            }
            .onDisappear {
                ticker.stop()
            }
    }

    private func advancePacing(elapsed: Double) {
        let currentTarget = latestTarget
        guard pacedContent.count < currentTarget.count else {
            ticker.stop()
            return
        }

        // Guard against pacedContent not being a prefix of currentTarget
        guard currentTarget.hasPrefix(pacedContent) else {
            pacedContent = currentTarget
            PacedTextCache.shared.set(messageId, currentTarget)
            ticker.stop()
            return
        }

        // Speed set to 400 chars/second for smoother vertical flow.
        let charsPerSecond = 400.0
        let charsToReveal = max(1, min(60, Int(round(elapsed * charsPerSecond))))
        let rawLength = min(currentTarget.count, pacedContent.count + charsToReveal)
        
        var targetLength = rawLength
        if rawLength < currentTarget.count {
            // Find next space or newline starting from rawLength
            let startIndex = currentTarget.index(currentTarget.startIndex, offsetBy: rawLength)
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
            
            // Snap to the next word or line boundary if it is within a short distance (up to 8 extra characters)
            if let b = boundary, (b - pacedContent.count) <= (charsToReveal + 8) {
                targetLength = min(currentTarget.count, b + 1)
            }
        }
        
        let nextIndex = currentTarget.index(currentTarget.startIndex, offsetBy: targetLength)
        let nextPacedText = String(currentTarget[..<nextIndex])
        pacedContent = nextPacedText
        PacedTextCache.shared.set(messageId, nextPacedText)

        if nextPacedText.count >= currentTarget.count {
            ticker.stop()
        }
    }
}

// MARK: - FrameTicker

/// A frame-synced timer using CADisplayLink to trigger updates aligned with the native screen refresh rate (60/120Hz).
/// Eliminates scheduling latency and thread-hopping stutters associated with Task.sleep or DispatchQueue.
@MainActor
final class FrameTicker: NSObject, ObservableObject {
    private var displayLink: CADisplayLink?
    private var onFrameCallback: ((Double) -> Void)?
    private var lastTimestamp: CFTimeInterval = 0

    func start(onFrame: @escaping (Double) -> Void) {
        guard displayLink == nil else {
            self.onFrameCallback = onFrame
            return
        }
        self.onFrameCallback = onFrame
        self.lastTimestamp = 0
        
        let link = CADisplayLink(target: self, selector: #selector(handleFrame))
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        onFrameCallback = nil
    }

    @objc private func handleFrame(link: CADisplayLink) {
        let current = link.timestamp
        let elapsed = lastTimestamp == 0 ? link.duration : (current - lastTimestamp)
        lastTimestamp = current
        onFrameCallback?(elapsed)
    }
}
