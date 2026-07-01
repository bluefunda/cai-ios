import SwiftUI

enum BFFont {

    // MARK: - Families

    static let displayFamily = "GeneralSans-Bold"
    static let bodyFamily = "Inter"
    static let bodyAltFamily = "DMSans"
    static let monoFamily = "RobotoMono-Regular"

    // Fallback: if General Sans is not registered, use the system font.
    // General Sans requires license confirmation for iOS bundle distribution.

    // MARK: - Platform scale
    //
    // Mac Catalyst has two idioms:
    //   • Mac Idiom  (TARGETED_DEVICE_FAMILY includes 6) — 100 % scale, no adjustment.
    //   • iPad Idiom (default)                           — 77 % scale, multiply to compensate.
    //
    // This single var is the ONE knob to turn when the user says "make sidebar
    // text bigger / smaller on Mac".  Change the `1.3` below and every sidebar
    // token updates automatically.
    //
    //   Current effective sizes on Mac with macScale:
    //     sidebarItem    13 × 1.3 × 0.77 ≈ 13 pt  (iPad idiom)
    //     sidebarItem    13 × 1.0        = 13 pt  (Mac  idiom)

    static var macScale: CGFloat {
        #if targetEnvironment(macCatalyst)
        return UIDevice.current.userInterfaceIdiom == .mac ? 1.0 : 1.3
        #else
        return 1.0
        #endif
    }

    // MARK: - Sidebar tokens
    //
    // Edit ONLY these base sizes to reshape the entire sidebar typography.
    // The macScale multiplier above handles platform compensation automatically.
    //
    //   sidebarHeader  — drawer title "BlueFunda AI"               (16 pt base)
    //   sidebarItem    — conversation rows, buttons, search field   (13 pt base)
    //   sidebarItemMed — profile name (medium weight variant)       (13 pt base)
    //   sidebarSection — group labels: Today / Yesterday            (11 pt base)
    //   sidebarMeta    — email, timestamps                          (12 pt base)
    //   toolbarIconPt  — pencil / hamburger / server SF Symbol size (19 pt base)

    static var sidebarHeader:  Font    { font(size: 16 * macScale, weight: .semibold) }
    static var sidebarItem:    Font    { font(size: 14 * macScale, weight: .regular)  }
    static var sidebarItemMed: Font    { font(size: 14 * macScale, weight: .medium)   }
    static var sidebarSection: Font    { font(size: 11 * macScale, weight: .semibold) }
    static var sidebarMeta:    Font    { font(size: 12 * macScale, weight: .regular)  }
    static var toolbarIconPt:  CGFloat { 19 * macScale }

    // MARK: - Response content tokens
    //
    // Controls all fonts inside AI response bubbles.
    // No macScale — response content renders in Mac Idiom at 100 % scale.
    //
    //   responseBody        — paragraphs, list items          (16 pt regular)
    //   responseBodyBold    — used by bold spans in lists     (16 pt semibold)
    //   responseH1/2/3/4    — in-response headings            (22/18/16/15 pt)
    //   responseTable       — table data cells                (14 pt regular)
    //   responseTableHeader — table header row                (14 pt semibold)
    //   responseCode        — fenced code blocks              (13 pt mono)

    static var responseBody:        Font { font(size: 16, weight: .regular)  }
    static var responseBodyBold:    Font { font(size: 16, weight: .semibold) }
    static var responseH1:          Font { font(size: 22, weight: .semibold) }
    static var responseH2:          Font { font(size: 18, weight: .semibold) }
    static var responseH3:          Font { font(size: 16, weight: .semibold) }
    static var responseH4:          Font { font(size: 15, weight: .medium)   }
    static var responseTable:       Font { font(size: 14, weight: .regular)  }
    static var responseTableHeader: Font { font(size: 14, weight: .semibold) }
    static var responseCode:        Font { .system(size: 13, design: .monospaced) }

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
    static let idpButton = font(size: 16, weight: .medium)
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