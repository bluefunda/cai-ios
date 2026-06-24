import SwiftUI

// MARK: - Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - Brand Color Tokens

enum BFColor {

    // MARK: Primary (Brand Blue)

    static let primary = Color(hex: "#1E64E7")
    static let primaryHover = Color(hex: "#1D4ED8")
    static let primaryPressed = Color(hex: "#1A56D4")
    static let primaryTint = Color(hex: "#EEF2FF")
    static let primarySubtle = Color(hex: "#F2F6FF")

    // MARK: Secondary (Navy / Deep Blue)

    static let secondary = Color(hex: "#1A305F")
    static let secondaryDark = Color(hex: "#111E38")
    static let secondarySidebar = Color(hex: "#1B1E37")
    static let secondaryAdmin = Color(hex: "#030D60")
    static let secondaryBorder = Color(hex: "#424660")

    // MARK: Brand Book Secondaries

    static let brandLightBlue = Color(hex: "#D9E2F3")
    static let brandHintBlue = Color(hex: "#FAF9FF")

    // MARK: Tertiary — Happy

    static let happyBlue = Color(hex: "#1E64E7")
    static let happyRed = Color(hex: "#E71E1E")
    static let happyOrange = Color(hex: "#E77E1E")
    static let happyMustard = Color(hex: "#E7D31E")
    static let happyGreen = Color(hex: "#1EE77A")
    static let happyPurple = Color(hex: "#8F1EE7")
    static let happyPink = Color(hex: "#E71E97")

    // MARK: Tertiary — Light (background tints)

    static let lightRed = Color(hex: "#F3D9D9")
    static let lightOrange = Color(hex: "#F3E4D9")
    static let lightMustard = Color(hex: "#F3F0D9")
    static let lightGreen = Color(hex: "#D9F3E3")
    static let lightBlue = Color(hex: "#D9E2F3")
    static let lightPurple = Color(hex: "#E9D9F3")
    static let lightPink = Color(hex: "#F3D9E9")

    // MARK: Tertiary — Deep (shadow/border)

    static let deepRed = Color(hex: "#5F1A1A")
    static let deepOrange = Color(hex: "#5F3B1A")
    static let deepMustard = Color(hex: "#5F581A")
    static let deepGreen = Color(hex: "#1A5F36")
    static let deepPurple = Color(hex: "#411A5F")
    static let deepPink = Color(hex: "#5F1A43")

    // MARK: Accent

    static let accentBlue = Color(hex: "#1361F5")
    static let accentIndigo = Color(hex: "#2563EB")
    static let accentGradientFrom = Color(hex: "#6366F1")
    static let accentGradientTo = Color(hex: "#8B5CF6")

    // MARK: Neutral Scale

    static let neutral0 = Color(hex: "#FFFFFF")
    static let neutral50 = Color(hex: "#F9FAFB")
    static let neutral100 = Color(hex: "#F3F4F6")
    static let neutral200 = Color(hex: "#E5E7EB")
    static let neutral300 = Color(hex: "#D1D5DB")
    static let neutral400 = Color(hex: "#9CA3AF")
    static let neutral500 = Color(hex: "#6B7280")
    static let neutral600 = Color(hex: "#4B5563")
    static let neutral700 = Color(hex: "#374151")
    static let neutral900 = Color(hex: "#1C1F25")
    static let neutral950 = Color(hex: "#000000")

    // MARK: Surfaces

    static let surfaceOffWhite = Color(hex: "#F9F9F9")
    static let surfaceTableHeader = Color(hex: "#FAFAFA")
    static let surfaceBlueWash = Color(hex: "#F8F9FF")
    static let surfaceChatReceiver = Color(hex: "#F5F5F5")
    static let surfaceChatSender = Color(hex: "#E8EBFA")

    // MARK: Semantic — Success

    static let success = Color(hex: "#56C04C")
    static let successBg = Color(hex: "#DFF9D3")
    static let successBorder = Color(hex: "#B6DFA2")

    // MARK: Semantic — Warning

    static let warning = Color(hex: "#F7AA16")
    static let warningBg = Color(hex: "#FFF3CA")
    static let warningBorder = Color(hex: "#EBD99D")

    // MARK: Semantic — Error

    static let error = Color(hex: "#EE1B1B")
    static let errorDelete = Color(hex: "#E72A1E")
    static let errorDanger = Color(hex: "#C2260E")

    // MARK: Semantic — Info

    static let info = Color(hex: "#1E64E7")
    static let infoBg = Color(hex: "#DBEFF5")
    static let infoBorder = Color(hex: "#92D0E2")

    // MARK: Text

    static let textPrimary = Color(hex: "#1F252D")
    static let textHeading = Color(hex: "#1E1E1E")
    static let textBody = Color(hex: "#1E293B")
    static let textSecondary = Color(hex: "#333333")
    static let textTertiary = Color(hex: "#5A5A5A")
    static let textPlaceholder = Color(hex: "#9CA3AF")
    static let textDisabled = Color(hex: "#929292")
    static let textMuted = Color(hex: "#7D7D7D")
    static let textInverse = Color(hex: "#FFFFFF")
    static let textLink = Color(hex: "#1E64E7")
    static let textChat = Color(hex: "#242424")
}
