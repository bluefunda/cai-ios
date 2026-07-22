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
}
