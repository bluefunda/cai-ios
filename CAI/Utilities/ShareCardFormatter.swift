import Foundation

/// Bounds the answer text rendered onto a shareable answer card
/// (bluefunda/cai-ios#197) so a truly extreme response (thousands of words)
/// doesn't produce an unusably huge image. Most real answers, including long
/// structured ones with tables and code blocks, fit under this comfortably —
/// this is a safety cap, not a normal-case truncation.
enum ShareCardFormatter {
    static let maxAnswerLength = 4000
    private static let continuedNote = "\n\n_Continued in the BlueFunda AI app…_"

    static func truncatedAnswer(_ text: String) -> String {
        guard text.count > maxAnswerLength else { return text }
        let cut = String(text.prefix(maxAnswerLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut + continuedNote
    }
}
