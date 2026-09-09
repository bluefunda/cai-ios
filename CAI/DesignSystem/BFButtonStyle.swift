import SwiftUI

struct BlueFundaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BFFont.bodyMedium)
            .foregroundColor(BFColor.textInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(BFColor.primary)
            .cornerRadius(BFRadius.lg)
            .bfShadow(configuration.isPressed ? BFShadow.md : BFShadow.lg)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(BFMotion.easingInOut, value: configuration.isPressed)
            .bfPointerHover()
    }
}

struct BlueFundaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BFFont.bodyMedium)
            .foregroundColor(BFColor.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(BFColor.neutral0)
            .cornerRadius(BFRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: BFRadius.lg)
                    .stroke(BFColor.neutral200, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(BFMotion.easingInOut, value: configuration.isPressed)
            .bfPointerHover()
    }
}

struct BlueFundaDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BFFont.bodyMedium)
            .foregroundColor(BFColor.textInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(BFColor.errorDelete)
            .cornerRadius(BFRadius.lg)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(BFMotion.easingInOut, value: configuration.isPressed)
            .bfPointerHover()
    }
}

extension ButtonStyle where Self == BlueFundaPrimaryButtonStyle {
    static var bfPrimary: BlueFundaPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == BlueFundaSecondaryButtonStyle {
    static var bfSecondary: BlueFundaSecondaryButtonStyle { .init() }
}

extension ButtonStyle where Self == BlueFundaDangerButtonStyle {
    static var bfDanger: BlueFundaDangerButtonStyle { .init() }
}

#if targetEnvironment(macCatalyst)
import UIKit

/// ViewModifier that toggles the macOS pointing-hand cursor on hover for Mac Catalyst.
/// Uses a push/pop stack on NSCursor and resets on disappear so the cursor stack is never leaked.
private struct BFPointerHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovered else { return }
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovered {
                    isHovered = false
                    NSCursor.pop()
                }
            }
    }
}
#endif

extension View {
    /// Shows the pointing-hand cursor on hover on Mac Catalyst.
    /// A no-op everywhere else (iOS/iPadOS touch has no mouse cursor).
    @ViewBuilder
    func bfPointerHover() -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(BFPointerHoverModifier())
        #else
        self
        #endif
    }
}
