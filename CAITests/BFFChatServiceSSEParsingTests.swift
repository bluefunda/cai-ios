import XCTest
@testable import CAI

/// Regression coverage for BFFChatService.parseSSEEvent — specifically the class of bug where
/// an unrecognized SSE event type that happens to carry a non-empty "content" field got silently
/// misclassified as a chat text chunk and spliced into the middle of the visible AI response
/// (e.g. "...coffee25.01|daily cups..." from a live_usage_pct tick landing between two real
/// stream_chunk frames). Each known non-chunk event type gets its own case here so a future
/// regression on any one of them fails immediately instead of showing up as corrupted user-facing
/// text weeks later.
final class BFFChatServiceSSEParsingTests: XCTestCase {
    private func sseEvent(_ json: String) -> String {
        "data: \(json)\n\n"
    }

    func testStreamChunk_ParsedAsChunk() {
        let event = BFFChatService.parseSSEEvent(sseEvent(#"{"type":"stream_chunk","content":"hello"}"#))
        guard case .chunk(let content, _, _) = event else {
            return XCTFail("Expected .chunk, got \(String(describing: event))")
        }
        XCTAssertEqual(content, "hello")
    }

    /// The exact bug: a live_usage_pct telemetry event's content ("pct|period", e.g.
    /// "25.01|daily") must never be surfaced as a chat chunk — it has nothing to do with the
    /// visible message text.
    func testLiveUsagePct_IsIgnored_NotTreatedAsChunk() {
        let event = BFFChatService.parseSSEEvent(sseEvent(#"{"type":"live_usage_pct","content":"25.01|daily"}"#))
        XCTAssertNil(event, "live_usage_pct must be ignored, not surfaced as a chat chunk")
    }

    func testUsageWarning_IsIgnored() {
        let event = BFFChatService.parseSSEEvent(sseEvent(#"{"type":"usage_warning","content":"80.00|monthly"}"#))
        XCTAssertNil(event)
    }

    func testBudgetExceeded_IsIgnored() {
        let event = BFFChatService.parseSSEEvent(sseEvent(#"{"type":"budget_exceeded","content":"100.00|daily"}"#))
        XCTAssertNil(event)
    }

    func testStreamProgress_IsIgnored() {
        let event = BFFChatService.parseSSEEvent(sseEvent(#"{"type":"stream_progress","content":"42"}"#))
        XCTAssertNil(event)
    }

    func testToolCall_IsIgnored() {
        let event = BFFChatService.parseSSEEvent(sseEvent(#"{"type":"tool_call","content":"search_web"}"#))
        XCTAssertNil(event)
    }

    func testStreamToolExecution_IsIgnored() {
        let event = BFFChatService.parseSSEEvent(sseEvent(#"{"type":"stream_tool_execution","content":"running"}"#))
        XCTAssertNil(event)
    }

    func testStreamArtifact_IsIgnored() {
        let event = BFFChatService.parseSSEEvent(sseEvent(#"{"type":"stream_artifact","content":"file.txt"}"#))
        XCTAssertNil(event)
    }

    /// A genuinely unknown, forward-compatible event type must also be ignored rather than
    /// falling back to "treat any non-empty content as a chat chunk" — that fallback was the
    /// root cause: it silently absorbed *any* future event type nobody had written a case for
    /// yet, rather than failing safe.
    func testUnknownFutureEventType_IsIgnored_NotAssumedToBeChunk() {
        let event = BFFChatService.parseSSEEvent(sseEvent(#"{"type":"some_new_event_type","content":"whatever"}"#))
        XCTAssertNil(event)
    }
}
