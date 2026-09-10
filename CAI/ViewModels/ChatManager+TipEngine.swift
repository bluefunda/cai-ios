import Foundation

// MARK: - Tip Engine (bluefunda/cai-ios#155)
// Split from the main ChatManager body to stay under SwiftLint's
// type_body_length/file_length limits, same as ChatManager+FileHistory.swift
// et al. Stored properties (tipInterestProfile, tipCatalog, tipAntiAnnoyance,
// tipRewardLog, activeTip, iapManager, lastTurnPersonaId) stay in
// ChatManager.swift — Swift extensions can't hold stored properties.
extension ChatManager {
    /// Called after each completed turn. See `TurnTopicSource` — no
    /// domain/intent/sap_confidence signal reaches iOS today, so this is a
    /// deliberately coarse, provisional placeholder derived from what's
    /// already observable in `sendMessage`.
    func recordCompletedTurnForTipEngine(assistantPersona: String?, wasRateLimited: Bool) {
        let outcome = TurnOutcome(
            hadError: self.error != nil,
            wasRateLimited: wasRateLimited,
            personaChanged: lastTurnPersonaId != nil && lastTurnPersonaId != assistantPersona,
            isFirstConversation: conversations.count <= 1
        )
        lastTurnPersonaId = assistantPersona
        tipInterestProfile.recordTurn(topics: tipTopicSource.topics(for: outcome))
        maybeShowTip()
    }

    /// Runs Phase 3 selection against the current catalog/interest profile
    /// and, if a tip is eligible, shows it. No-ops (leaves `activeTip`
    /// alone) rather than replacing an already-showing tip, since
    /// `AntiAnnoyance`'s 1-per-session cap would reject a second selection
    /// anyway.
    private func maybeShowTip() {
        guard activeTip == nil else { return }
        let context = TipSelectionContext(
            personaId: (personaEnabled ? persona : .general).id,
            isGeneralMode: !personaEnabled || persona == .general,
            hasActiveSubscription: iapManager?.hasActiveSubscription ?? false
        )
        guard let selected = TipSelector.select(
            from: tipCatalog.entries,
            profile: tipInterestProfile.vector(),
            antiAnnoyance: tipAntiAnnoyance,
            context: context
        ) else { return }
        activeTip = selected
        tipAntiAnnoyance.recordShown(tipId: selected.id, family: selected.family)
        tipRewardLog.log(
            .shown, tipId: selected.id, catalogVersion: selected.catalogVersion,
            interestVector: tipInterestProfile.vector()
        )
    }

    func dismissActiveTip() {
        guard let tip = activeTip else { return }
        tipAntiAnnoyance.recordDismissed(family: tip.family)
        tipRewardLog.log(
            .dismissed, tipId: tip.id, catalogVersion: tip.catalogVersion,
            interestVector: tipInterestProfile.vector()
        )
        activeTip = nil
    }

    func tapActiveTip() {
        guard let tip = activeTip else { return }
        tipAntiAnnoyance.recordTapped(tipId: tip.id)
        tipRewardLog.log(
            .tapped, tipId: tip.id, catalogVersion: tip.catalogVersion,
            interestVector: tipInterestProfile.vector()
        )
        activeTip = nil
    }
}
