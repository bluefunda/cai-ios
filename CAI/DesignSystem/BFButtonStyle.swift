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
