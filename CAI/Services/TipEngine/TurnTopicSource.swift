import Foundation

/// The signals about one completed chat turn that are actually observable
/// client-side today. Deliberately narrow: `BFFChatService.parseSSEEvent`
/// only surfaces `stream_end`'s `total_chunks`/`full_content`/`stopped` (and
/// silently drops `tool_call`/`stream_tool_execution`), so there is no
/// per-turn MCP-tool-usage or "first run" signal to plug in yet.
struct TurnOutcome {
    let hadError: Bool
    let wasRateLimited: Bool
    let personaChanged: Bool
    let isFirstConversation: Bool
}

/// Maps a completed turn to the `TipTopic`s it touched, for
/// `InterestProfile.recordTurn`.
///
/// This is the seam issue #156 calls "subscribe to the existing
/// cai-llm-router output (domain, intent, sap_confidence)" — that signal
/// does not reach iOS today (verified: no such field anywhere in the wire
/// models, DTOs, or SSE parsing), and even if it did, tip-catalog's
/// `TipTopic` taxonomy is about app/tool usage (mcp, model-selection,
/// cost-budget, ...), not SAP functional domains, so it wouldn't align
/// without its own translation layer anyway. `HeuristicHelloTurnTopicSource`
/// below is a deliberately simple, deterministic placeholder — swap in a
/// real backend-classification-backed source later by conforming to this
/// protocol, without touching `InterestProfile` or its callers.
protocol TurnTopicSource {
    func topics(for outcome: TurnOutcome) -> [TipTopic]
}

/// Deterministic mapping from `TurnOutcome`'s observable signals to topics —
/// explicitly not a classifier/model, per issue #156's "do not add a
/// classifier" constraint.
struct HeuristicTurnTopicSource: TurnTopicSource {
    func topics(for outcome: TurnOutcome) -> [TipTopic] {
        var topics: [TipTopic] = []
        if outcome.hadError { topics.append(.diagnostics); topics.append(.errors) }
        if outcome.wasRateLimited { topics.append(.costBudget) }
        if outcome.personaChanged { topics.append(.modelSelection) }
        if outcome.isFirstConversation { topics.append(.onboarding) }
        return topics
    }
}
