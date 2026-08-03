import Foundation

/// Build-time and runtime feature flags.
///
/// Defaults are set conservatively (off). Override any flag at runtime via
/// UserDefaults — useful for internal testing without a code change:
///
///   UserDefaults.standard.set(true, forKey: BFFeatureFlags.Keys.fileUpload)
///
/// Or via an Xcode scheme launch argument:  -bf_file_upload YES
///
enum BFFeatureFlags {
    enum Keys {
        static let fileUpload = "bf_feature_file_upload"
        static let personaWire = "bf_feature_persona_wire"
    }

    /// File attachment (photo library + document picker) in the chat input bar.
    /// Enabled by default now that attachments persist locally via LocalFileStore
    /// and the backend upload + fileUrl contract is confirmed production-ready.
    /// Override to false via UserDefaults/launch argument to kill-switch it.
    static var fileUploadEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.fileUpload) != nil
            ? UserDefaults.standard.bool(forKey: Keys.fileUpload)
            : true
    }

    /// Whether the resolved persona (global default or per-message override)
    /// is actually sent to the backend on `ChatRequest.persona`. On by default
    /// (2026-08-03) — backend-side work (cai-bff#110-112, cai-llm-router#242-244,
    /// cai-mcp-go#180-182) shipped and confirmed working end-to-end in a live
    /// device test (groq and gemini models; IS-U persona verified against real
    /// SAP tcodes). Override to false via UserDefaults/launch argument to
    /// kill-switch it if a regression turns up.
    static var personaWireEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.personaWire) != nil
            ? UserDefaults.standard.bool(forKey: Keys.personaWire)
            : true
    }
}
