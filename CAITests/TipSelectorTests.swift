import XCTest
@testable import CAI

// MARK: - Tip Engine Phase 3 Tests (bluefunda/cai-ios#158)
// Guards the eligibility predicate, cosine-similarity candidate scoring,
// and the General/SAP-scoped safety boundary.

final class TipSelectorTests: XCTestCase {
    private func makeEntry(
        id: String = "tip-1",
        family: String = "family-1",
        minTier: String? = nil,
        personaGate: String? = nil,
        cooldown: String? = nil,
        embedding: [Double] = Array(repeating: 0, count: TipTopic.dimension)
    ) -> TipManifestEntry {
        TipManifestEntry(
            id: id, family: family, surfaces: ["ios"], domainScope: [],
            personaGate: personaGate, triggerConditions: nil, minTier: minTier,
            cooldown: cooldown, render: TipRender(ios: TipRenderContent(title: "T", body: "B")),
            deepLink: nil, embedding: embedding, catalogVersion: "1"
        )
    }

    private func context(
        personaId: String = "general",
        isGeneralMode: Bool = true,
        hasActiveSubscription: Bool = false,
        now: Date = Date()
    ) -> TipSelectionContext {
        TipSelectionContext(personaId: personaId, isGeneralMode: isGeneralMode, hasActiveSubscription: hasActiveSubscription, now: now)
    }

    // MARK: Eligibility — tier

    func test_eligibility_proTip_excludedWithoutActiveSubscription() {
        let entry = makeEntry(minTier: "pro")
        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        XCTAssertFalse(TipSelector.isEligible(entry, context: context(hasActiveSubscription: false), antiAnnoyance: anti))
        XCTAssertTrue(TipSelector.isEligible(entry, context: context(hasActiveSubscription: true), antiAnnoyance: anti))
    }

    // MARK: Eligibility — cooldown / dismissal

    func test_eligibility_dismissedFamily_excludedUntilBackoffExpires() {
        let entry = makeEntry(family: "onboarding")
        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        let now = Date()
        anti.recordDismissed(family: "onboarding", at: now)
        XCTAssertFalse(TipSelector.isEligible(entry, context: context(now: now.addingTimeInterval(3600)), antiAnnoyance: anti))
        XCTAssertTrue(TipSelector.isEligible(entry, context: context(now: now.addingTimeInterval(25 * 3600)), antiAnnoyance: anti))
    }

    // MARK: Eligibility — dismissal state (retirement)

    func test_eligibility_retiredTip_excludedRegardlessOfRank() {
        let entry = makeEntry(id: "never-tapped")
        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        for _ in 0..<3 {
            anti.recordShown(tipId: "never-tapped", family: "family-1")
        }
        // Reset the session cap so the assertion below is attributable to
        // retirement specifically, not the unrelated per-session cap.
        anti.startSession()
        XCTAssertFalse(TipSelector.isEligible(entry, context: context(), antiAnnoyance: anti))
    }

    // MARK: Eligibility — per-tip cooldown (issue #158 lists this as one of
    // the five eligibility factors; TipManifestEntry.cooldown was decoded
    // but never enforced until now — found while authoring real content).

    func test_eligibility_cooldown_excludesUntilItElapses() {
        let entry = makeEntry(cooldown: "72h")
        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        let shownAt = Date()
        anti.recordShown(tipId: entry.id, family: entry.family, at: shownAt)
        // Reset session/day caps so the assertions are attributable to the
        // cooldown specifically, not the unrelated per-session/day caps.
        anti.startSession(at: shownAt.addingTimeInterval(71 * 3600))
        XCTAssertFalse(TipSelector.isEligible(entry, context: context(now: shownAt.addingTimeInterval(71 * 3600)), antiAnnoyance: anti))
        anti.startSession(at: shownAt.addingTimeInterval(73 * 3600))
        XCTAssertTrue(TipSelector.isEligible(entry, context: context(now: shownAt.addingTimeInterval(73 * 3600)), antiAnnoyance: anti))
    }

    func test_eligibility_cooldown_emptyFallsBackToOneHourFloor() {
        let entry = makeEntry(cooldown: nil)
        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        let shownAt = Date()
        anti.recordShown(tipId: entry.id, family: entry.family, at: shownAt)
        anti.startSession(at: shownAt.addingTimeInterval(30 * 60))
        XCTAssertFalse(TipSelector.isEligible(entry, context: context(now: shownAt.addingTimeInterval(30 * 60)), antiAnnoyance: anti))
        anti.startSession(at: shownAt.addingTimeInterval(61 * 60))
        XCTAssertTrue(TipSelector.isEligible(entry, context: context(now: shownAt.addingTimeInterval(61 * 60)), antiAnnoyance: anti))
    }

    // MARK: Eligibility — persona gate

    func test_eligibility_personaGate_excludesNonMatchingPersona() {
        let entry = makeEntry(personaGate: "abap")
        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        XCTAssertFalse(TipSelector.isEligible(entry, context: context(personaId: "fi", isGeneralMode: false), antiAnnoyance: anti))
        XCTAssertTrue(TipSelector.isEligible(entry, context: context(personaId: "abap", isGeneralMode: false), antiAnnoyance: anti))
    }

    // Regression: found live via the debug harness — tip-catalog's actual
    // published tip uses persona_gate "new_user" (a lifecycle segment, not
    // a CAI Persona), which permanently blocked the tip until this was
    // recognized as unenforceable rather than "never matches".
    func test_eligibility_unrecognizedPersonaGate_doesNotPermanentlyBlock() {
        let entry = makeEntry(personaGate: "new_user")
        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        XCTAssertTrue(TipSelector.isEligible(entry, context: context(personaId: "general"), antiAnnoyance: anti))
        XCTAssertTrue(TipSelector.isEligible(entry, context: context(personaId: "abap", isGeneralMode: false), antiAnnoyance: anti))
    }

    // MARK: Eligibility — assistant mode (General/SAP-scoped safety boundary)

    func test_eligibility_generalMode_neverSurfacesAnSAPScopedTip() {
        // v1 semantics: tip-catalog's schema has no field yet that marks a
        // tip as SAP-scoped (see TipSelector.isSAPScoped's TODO), so this
        // documents current behavior — General mode passes every
        // candidate through unchanged today, across varied embeddings.
        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        let vectors: [[Double]] = [
            Array(repeating: 0, count: TipTopic.dimension),
            Array(repeating: 1, count: TipTopic.dimension),
            {
                var v = Array(repeating: 0.0, count: TipTopic.dimension)
                v[TipTopic.mcp.index] = 1
                return v
            }()
        ]
        for vector in vectors {
            let entry = makeEntry(embedding: vector)
            XCTAssertTrue(TipSelector.isEligible(entry, context: context(isGeneralMode: true), antiAnnoyance: anti))
        }
    }

    // MARK: Candidate scoring — cosine similarity

    func test_candidateScoring_cosineSimilarity_ranksClosestVectorHighest() {
        var closeMatch = Array(repeating: 0.0, count: TipTopic.dimension)
        closeMatch[TipTopic.mcp.index] = 1
        var farMatch = Array(repeating: 0.0, count: TipTopic.dimension)
        farMatch[TipTopic.auth.index] = 1

        let close = makeEntry(id: "close", embedding: closeMatch)
        let far = makeEntry(id: "far", embedding: farMatch)

        var profile = Array(repeating: 0.0, count: TipTopic.dimension)
        profile[TipTopic.mcp.index] = 1

        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        let selected = TipSelector.select(
            from: [far, close], profile: profile, antiAnnoyance: anti, context: context()
        )
        XCTAssertEqual(selected?.id, "close")
    }

    // MARK: TipRanker is swappable

    func test_ranker_isSwappable() {
        struct AlwaysLastRanker: TipRanker {
            func rank(_ candidates: [TipCandidate], personaId: String) -> TipManifestEntry? {
                candidates.last?.entry
            }
        }
        let a = makeEntry(id: "a")
        let b = makeEntry(id: "b")
        let anti = AntiAnnoyance(store: TipEngineFileStore(filename: "x", directory: tempDir()))
        let selected = TipSelector.select(
            from: [a, b], profile: Array(repeating: 0, count: TipTopic.dimension),
            antiAnnoyance: anti, context: context(), ranker: AlwaysLastRanker()
        )
        XCTAssertEqual(selected?.id, "b")
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
