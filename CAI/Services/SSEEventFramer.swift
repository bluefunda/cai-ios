import Foundation

/// Incrementally reassembles raw SSE bytes into parsed `ChatEvent`s.
///
/// A `"\n\n"` is not trusted as a real event boundary until the bytes before
/// it actually parse as a complete event. The previous implementation
/// (inline in `BFFChatService.sendMessage`) removed bytes from the buffer the
/// moment it found a `"\n\n"`, *before* attempting to parse them — so any
/// parse failure (malformed input, an unexpected mid-stream artifact) discarded
/// that data permanently with no error surfaced anywhere. This version only
/// consumes bytes once they've been proven to parse; otherwise it keeps them
/// and keeps scanning forward. Strictly a hardening measure over the old
/// behavior — never worse, and safer against classes of malformed/misaligned
/// input the old code had no defense against.
struct SSEEventFramer {
    private var buffer = Data()
    private static let delimiter = Data([0x0A, 0x0A]) // "\n\n"

    /// Feeds a single newly-received byte, returning any complete events that
    /// become available. Mirrors the network loop's per-byte reads.
    mutating func feed(byte: UInt8) -> [ChatEvent] {
        buffer.append(byte)
        // A "\n\n" can only complete when we just appended a newline.
        guard byte == 0x0A else { return [] }

        var events: [ChatEvent] = []
        var searchStart = buffer.startIndex
        while let range = buffer.range(of: Self.delimiter, options: [], in: searchStart..<buffer.endIndex) {
            let candidate = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            if let event = Self.parseEvent(String(decoding: candidate, as: UTF8.self)) {
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                events.append(event)
                searchStart = buffer.startIndex
                if event.isTerminal { break }
            } else {
                // Not a genuine event boundary (e.g. a blank line inside the
                // content itself) — keep the bytes, look further ahead.
                searchStart = range.upperBound
            }
        }
        return events
    }

    /// Convenience for feeding a whole chunk of bytes at once (e.g. in tests).
    mutating func feed(data: Data) -> [ChatEvent] {
        data.reduce(into: [ChatEvent]()) { events, byte in
            events.append(contentsOf: feed(byte: byte))
        }
    }

    static func parseEvent(_ eventText: String) -> ChatEvent? {
        var eventData: String?

        let lines = eventText.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data:") {
                let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if eventData == nil {
                    eventData = data
                } else {
                    eventData! += "\n" + data
                }
            }
        }

        guard let data = eventData,
              !data.isEmpty,
              let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        let type = json["type"] as? String ?? ""

        switch type {
        case "stream_start":
            let chatId = json["chat_id"] as? String ?? json["chatId"] as? String ?? ""
            let sessionId = json["session_id"] as? String ?? json["sessionId"] as? String ?? ""
            return .streamStart(chatId: chatId, sessionId: sessionId)

        case "stream_chunk":
            let content = json["content"] as? String ?? ""
            let chunkId = json["chunk_id"] as? Int ?? json["chunkId"] as? Int ?? 0
            let totalLength = json["total_content_length"] as? Int ?? json["totalContentLength"] as? Int ?? 0
            return .chunk(content: content, chunkId: chunkId, totalLength: totalLength)

        case "stream_end":
            let totalChunks = json["total_chunks"] as? Int ?? json["totalChunks"] as? Int ?? 0
            let fullContent = json["full_content"] as? String ?? json["fullContent"] as? String ?? ""
            let stopped = json["stopped"] as? Bool ?? false
            return .streamEnd(totalChunks: totalChunks, fullContent: fullContent, stopped: stopped)

        case "stream_heartbeat":
            let sessionId = json["session_id"] as? String ?? json["sessionId"] as? String ?? ""
            let chunks = json["chunks"] as? Int ?? 0
            let contentLength = json["content_length"] as? Int ?? json["contentLength"] as? Int ?? 0
            return .heartbeat(sessionId: sessionId, chunks: chunks, contentLength: contentLength)

        case "stream_error", "error":
            let message = json["message"] as? String ?? json["error"] as? String ?? "Unknown error"
            let details = json["details"] as? String
            return .error(message: message, details: details)

        case "rate_limited":
            let period = json["period"] as? String ?? "daily"
            let resetLabel = json["reset_label"] as? String ?? ""
            return .rateLimited(period: period, resetLabel: resetLabel)

        default:
            // Try to parse as chunk if content exists
            if let content = json["content"] as? String, !content.isEmpty {
                return .chunk(content: content, chunkId: 0, totalLength: 0)
            }
            return nil
        }
    }
}
