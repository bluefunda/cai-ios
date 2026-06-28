import SwiftUI

enum BFFont {

    // MARK: - Families

    static let displayFamily = "GeneralSans-Bold"
    static let bodyFamily = "Inter"
    static let bodyAltFamily = "DMSans"
    static let monoFamily = "RobotoMono-Regular"

    // Fallback: if General Sans is not registered, use the system font.
    // General Sans requires license confirmation for iOS bundle distribution.

    // MARK: - Type Scale

    static let display = font(size: 50, weight: .bold)
    static let h1 = font(size: 48, weight: .bold)
    static let h2 = font(size: 38, weight: .bold)
    static let h2App = font(size: 32, weight: .bold)
    static let h3 = font(size: 28, weight: .semibold)
    static let h4 = font(size: 24, weight: .semibold)
    static let h5 = font(size: 20, weight: .bold)
    static let bodyLarge = font(size: 20, weight: .regular)
    static let bodyMedium = font(size: 18, weight: .medium)
    static let body = font(size: 18, weight: .regular)
    static let bodySmall = font(size: 15, weight: .regular)
    static let caption = font(size: 13, weight: .semibold)
    static let micro = font(size: 12, weight: .regular)
    static let code = Font.system(size: 14, design: .monospaced)

    // MARK: - Label Style

    static let captionKerning: CGFloat = 0.91

    // MARK: - Helpers

    private static func font(size: CGFloat, weight: Font.Weight) -> Font {
        if let custom = customFont(size: size, weight: weight) {
            return custom
        }
        return .system(size: size, weight: weight)
    }

    private static func customFont(size: CGFloat, weight: Font.Weight) -> Font? {
        let name: String
        switch weight {
        case .bold: name = "GeneralSans-Bold"
        case .semibold: name = "GeneralSans-Semibold"
        case .medium: name = "GeneralSans-Medium"
        case .regular: name = "GeneralSans-Regular"
        case .light: name = "GeneralSans-Light"
        default: name = "GeneralSans-Regular"
        }
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return nil
    }
}

// MARK: - Form Label Modifier

struct BFFormLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(BFFont.caption)
            .kerning(BFFont.captionKerning)
            .foregroundStyle(BFColor.textSecondary)
    }
}

extension View {
    func bfFormLabel() -> some View {
        modifier(BFFormLabel())
    }
}
