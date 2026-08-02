import XCTest
@testable import CAI

// MARK: - SSE Event Framer Tests
//
// Extracted from BFFChatService.sendMessage's inline byte-buffer loop so the
// framing logic (deciding when a "\n\n" is a real event boundary) is directly
// testable. The original inline version removed bytes from the buffer as
// soon as it found a "\n\n", *before* confirming they parsed as a complete
// event — meaning any parse failure permanently discarded that data with no
// error surfaced. This version only removes bytes once they've been proven
// to parse, and otherwise keeps scanning forward instead of destroying them.
//
// Note: while investigating a real report of a chat response truncating
// silently in the UI, the most direct "premature \n\n mid-event" reproduction
// turned out to be hard to construct as a realistic, recoverable case — SSE's
// line-based framing means a stray blank line is, per spec, a genuine event
// terminator, and a raw unescaped newline embedded in a JSON string simply
// isn't valid JSON no matter how much is buffered. So this fix is kept as a
// defensive hardening measure (strictly safer than the old code, never
// worse), not a confirmed root-cause fix for that report.

final class SSEEventFramerTests: XCTestCase {
    func test_wellFormedSingleEvent_parsesCorrectly() {
        var framer = SSEEventFramer()
        let raw = "data: {\"type\":\"stream_chunk\",\"content\":\"Hello\",\"chunk_id\":1,\"total_content_length\":5}\n\n"
        let events = framer.feed(data: Data(raw.utf8))

        XCTAssertEqual(events.count, 1)
        guard case .chunk(let content, let chunkId, let totalLength) = events.first else {
            return XCTFail("expected a chunk event")
        }
        XCTAssertEqual(content, "Hello")
        XCTAssertEqual(chunkId, 1)
        XCTAssertEqual(totalLength, 5)
    }

    func test_multipleEventsFedTogether_parseInOrder() {
        var framer = SSEEventFramer()
        let raw = "data: {\"type\":\"stream_chunk\",\"content\":\"one\",\"chunk_id\":1,\"total_content_length\":6}\n\n" +
                  "data: {\"type\":\"stream_chunk\",\"content\":\"two\",\"chunk_id\":2,\"total_content_length\":6}\n\n"
        let events = framer.feed(data: Data(raw.utf8))

        XCTAssertEqual(events.count, 2)
        guard case .chunk(let first, _, _) = events[0], case .chunk(let second, _, _) = events[1] else {
            return XCTFail("expected two chunk events")
        }
        XCTAssertEqual(first, "one")
        XCTAssertEqual(second, "two")
    }

    /// The realistic path: bytes trickle in one at a time from the network,
    /// same as BFFChatService's actual `for try await byte in bytes` loop.
    /// Nothing should be yielded until the terminating "\n\n" has actually
    /// arrived, and the full content must survive being assembled one byte
    /// at a time.
    func test_eventBytesDeliveredOneAtATime_bufferedUntilComplete() {
        var framer = SSEEventFramer()
        let raw = "data: {\"type\":\"stream_chunk\",\"content\":\"Hello world\",\"chunk_id\":1,\"total_content_length\":11}\n\n"

        var allEvents: [ChatEvent] = []
        for byte in Array(raw.utf8) {
            allEvents.append(contentsOf: framer.feed(byte: byte))
        }

        XCTAssertEqual(allEvents.count, 1)
        guard case .chunk(let content, _, _) = allEvents.first else {
            return XCTFail("expected a chunk event")
        }
        XCTAssertEqual(content, "Hello world")
    }

    func test_terminalEvent_isFlaggedCorrectly() {
        var framer = SSEEventFramer()
        let raw = "data: {\"type\":\"stream_end\",\"total_chunks\":2,\"full_content\":\"done\",\"stopped\":false}\n\n"
        let events = framer.feed(data: Data(raw.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isTerminal)
    }

    func test_genuinelyMalformedJSON_isDroppedWithoutHanging() {
        var framer = SSEEventFramer()
        // No amount of buffering makes this valid JSON. The framer must not
        // loop forever — once no further delimiter exists in the buffer it
        // simply returns, waiting for more bytes (none arrive in this test).
        let raw = "data: {not json at all\n\n"
        let events = framer.feed(data: Data(raw.utf8))

        XCTAssertTrue(events.isEmpty)
    }
}
