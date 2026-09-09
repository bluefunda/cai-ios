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

extension View {
    /// Drives Mac Catalyst's (and a mouse/trackpad-connected iPad's) pointer interaction —
    /// showing the pointing-hand cursor on hover, plus a subtle highlight — for a custom
    /// tappable control built from a plain Image or Text. A no-op on touch-only devices.
    /// SwiftUI's Button isn't backed by a real UIButton, so unlike a native AppKit/UIKit
    /// control it doesn't get this for free; without it there's nothing on Mac Catalyst to
    /// indicate "this is clickable" until the actual click. .pointerStyle(_:) is NOT this —
    /// that modifier only exists on visionOS, not Mac Catalyst, despite the similar name.
    /// Apply to any button-like control across the app, not just one place.
    func bfPointerHover() -> some View {
        hoverEffect(.highlight)
    }
}
