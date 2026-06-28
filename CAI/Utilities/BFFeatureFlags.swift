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
    /// Disabled by default; enable for internal builds or once backend is production-ready.
    static var fileUploadEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.fileUpload) != nil
            ? UserDefaults.standard.bool(forKey: Keys.fileUpload)
            : false
    }
}
