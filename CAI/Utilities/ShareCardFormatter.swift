import Foundation

/// Bounds the answer text rendered onto a shareable answer card
/// (bluefunda/cai-ios#197) so the exported image stays a reasonable, readable
/// size instead of growing arbitrarily tall for long responses.
enum ShareCardFormatter {
    static let maxAnswerLength = 600

    static func truncatedAnswer(_ text: String) -> String {
        guard text.count > maxAnswerLength else { return text }
        return String(text.prefix(maxAnswerLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
