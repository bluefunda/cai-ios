import Foundation

/// Heuristically recognizes pasted SAP ST22 short dump text
/// (bluefunda/cai-ios#182), so the composer can offer to decode it instead of
/// sending it as a plain question.
enum ST22DumpDetector {
    /// Phrases that commonly appear on an ST22 short dump screen (English UI).
    /// None of these alone is distinctive enough — chat messages can
    /// legitimately contain any single one — so detection requires several
    /// to co-occur.
    private static let markers = [
        "short text",
        "what happened",
        "error analysis",
        "runtime errors",
        "abap program",
        "termination occurred",
        "system environment",
        "except.",
    ]

    /// Minimum pasted-text length before running the check at all — avoids
    /// false positives on short, ordinary messages that happen to contain one
    /// marker phrase.
    private static let minimumLength = 40
    private static let minimumMarkerMatches = 3

    static func looksLikeDump(_ text: String) -> Bool {
        guard text.count >= minimumLength else { return false }
        let lowercased = text.lowercased()
        let matches = markers.filter { lowercased.contains($0) }.count
        return matches >= minimumMarkerMatches
    }
}
