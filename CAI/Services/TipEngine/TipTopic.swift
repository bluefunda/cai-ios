import Foundation

/// The shared tip taxonomy, vendored from `bluefunda/tipcatalog`'s `Topics`
/// (topics.go, v1.1.0). Order is significant — it fixes each case's
/// position in the interest vector (`InterestProfile.vector`) and must stay
/// byte-for-byte in sync with the catalog's `Topics` slice, since a tip's
/// `embedding` is a multi-hot vector over that same ordering. Reordering or
/// removing a case here without a matching, coordinated change upstream
/// silently breaks every cosine-similarity comparison in `TipSelector`.
///
/// Appending a new case at the end (mirroring an appended upstream topic)
/// is safe.
enum TipTopic: String, CaseIterable, Codable {
    case auth
    case sessions
    case mcp
    case memory
    case plugins
    case worktree
    case costBudget = "cost-budget"
    case modelSelection = "model-selection"
    case outputFormat = "output-format"
    case config
    case diagnostics
    case updates
    case automation
    case onboarding
    case errors

    /// This case's fixed position in every `TipTopic`-indexed vector.
    var index: Int {
        Self.allCases.firstIndex(of: self)!
    }

    /// Number of dimensions in a `TipTopic`-indexed vector — must equal
    /// tipcatalog's `EmbeddingDim`.
    static var dimension: Int { allCases.count }
}
