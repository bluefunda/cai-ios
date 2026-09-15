import SwiftUI
import UIKit

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

    /// A color that actually adapts to the device's light/dark appearance — unlike a bare
    /// `Color(hex:)`, which stays fixed regardless of theme. Needed for any token meant to read
    /// correctly (not clash with a black background) whether the user is in light or dark mode,
    /// on any device (this is a UITraitCollection-driven UIColor under the hood, so it updates
    /// live on a theme switch rather than needing a relaunch).
    init(lightHex: String, darkHex: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: darkHex)) : UIColor(Color(hex: lightHex))
        })
    }
}

// MARK: - Brand Color Tokens

enum BFColor {

    // MARK: Primary (Brand Blue)

    static let primary = Color(hex: "#1E64E7")
    static let primaryHover = Color(hex: "#1D4ED8")
    static let primaryPressed = Color(hex: "#1A56D4")
    // A bare Color(hex:) stays fixed regardless of theme — in dark mode this rendered as a
    // stark near-white pill (the composer's mode picker, the "Upgrade to Pro" row) clashing
    // hard against a black background, with default `.primary`-label text (white in dark mode)
    // landing on a near-white background. lightHex/darkHex makes it adapt on every device.
    static let primaryTint = Color(lightHex: "#EEF2FF", darkHex: "#1B2440")
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

    // MARK: Adaptive App Chrome
    //
    // The surfaces the chat shell is built from — sidebar, canvas, composer,
    // message cards, hairline rules. All declared with lightHex/darkHex (never
    // a bare Color(hex:)) so they track the device appearance instead of
    // freezing to their light-mode value; see the note on `primaryTint` above
    // for the bug that pattern exists to prevent.
    //
    // Values are tuned so the three layers read as distinct depths in both
    // themes: canvas (furthest back) < sidebar < raised/sunken (cards, fields).

    /// Main chat background — the page the messages sit on.
    static let surfaceCanvas = Color(lightHex: "#FFFFFF", darkHex: "#131314")
    /// Sidebar / navigation column, one step off the canvas.
    static let surfaceSidebar = Color(lightHex: "#F7F8FA", darkHex: "#1B1C1E")
    /// Lifted elements that should read as floating above the canvas (composer).
    static let surfaceRaised = Color(lightHex: "#FFFFFF", darkHex: "#1E1F22")
    /// Recessed fills: search fields, attachment chips, inactive controls.
    static let surfaceSunken = Color(lightHex: "#EEF0F3", darkHex: "#26282C")
    /// Assistant response card.
    static let surfaceCard = Color(lightHex: "#F6F7F9", darkHex: "#1D1E21")
    /// 1px rules and control borders — replaces hard `Divider()` lines.
    static let hairline = Color(lightHex: "#E4E6EA", darkHex: "#303236")
    /// Pointer-hover fill for sidebar rows and icon buttons.
    static let rowHover = Color(lightHex: "#E9ECF1", darkHex: "#26282C")

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

// MARK: - Hairline Rule

/// A 0.5-pt rule in `BFColor.hairline`. Used instead of `Divider()` wherever a
/// separator should read as a quiet boundary rather than a hard line — SwiftUI's
/// `Divider` renders at the system separator colour and full opacity, which is
/// noticeably heavier than the rules Gemini / Copilot's desktop apps use.
struct BFHairline: View {
    var body: some View {
        Rectangle()
            .fill(BFColor.hairline)
            .frame(height: 0.5)
    }
}
