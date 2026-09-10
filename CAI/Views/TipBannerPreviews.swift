import SwiftUI

// MARK: - Preview-only, mirrors RateLimitBannerPreviews.swift's convention.
// No snapshot-testing library exists in this codebase yet — these previews
// are the actual light/dark visual check for the tip card (bluefunda/cai-ios#155).

private let previewTip = TipManifestEntry(
    id: "ios-sap-persona",
    family: "ios-persona",
    surfaces: ["ios"],
    domainScope: ["config", "model-selection"],
    personaGate: nil,
    triggerConditions: nil,
    minTier: "free",
    cooldown: "72h",
    render: TipRender(ios: TipRenderContent(
        title: "Get SAP-specific answers",
        body: "Turn on Persona in the composer and pick your specialty (ABAP, BASIS, FI, and more) so answers use the right terminology and depth for your role."
    )),
    deepLink: nil,
    embedding: Array(repeating: 0, count: TipTopic.dimension),
    catalogVersion: "1"
)

#Preview("Tip Banner — Light") {
    TipBannerView(tip: previewTip, onDismiss: {}, onTap: {})
        .preferredColorScheme(.light)
}

#Preview("Tip Banner — Dark") {
    TipBannerView(tip: previewTip, onDismiss: {}, onTap: {})
        .preferredColorScheme(.dark)
}
