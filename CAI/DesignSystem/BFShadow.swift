import SwiftUI

enum BFShadow {
    static let sm = BFShadowStyle(color: .black.opacity(0.10), radius: 2, x: 0, y: 2)
    static let md = BFShadowStyle(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
    static let lg = BFShadowStyle(color: Color(hex: "#1361F5").opacity(0.30), radius: 6, x: 0, y: 4)
    static let lgHover = BFShadowStyle(color: Color(hex: "#1361F5").opacity(0.40), radius: 6, x: 0, y: 4)
    static let xl = BFShadowStyle(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
    static let overlay = Color.black.opacity(0.40)
}

struct BFShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func bfShadow(_ style: BFShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
