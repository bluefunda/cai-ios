import SwiftUI

enum BFRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12

    // MARK: - Desktop-app chrome
    //
    // Larger, softer corners used by the chat surfaces (composer, message
    // cards, sidebar rows). Matches the roundness Gemini / Copilot's macOS
    // apps use — the smaller sm…xl steps above stay for form controls.

    static let xl2: CGFloat = 16
    static let card: CGFloat = 20
    static let composer: CGFloat = 26
    static let row: CGFloat = 10

    static let full: CGFloat = 9999
}
