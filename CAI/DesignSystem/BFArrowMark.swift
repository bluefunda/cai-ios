import SwiftUI

/// The brand "arrow" symbol (Brand_Guidelines/01_Logos/Symbol) as a vector
/// `Shape`, traced from its source SVG (viewBox 364×190) — kept as code
/// rather than a bundled image so it scales/recolors/animates cleanly at any
/// size, and doesn't depend on the (currently unpopulated) `LogoSymbol`
/// image set in Assets.xcassets/Logos.
struct BFArrowMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w: CGFloat = 364
        let h: CGFloat = 190
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / w * rect.width, y: rect.minY + y / h * rect.height)
        }

        var path = Path()
        path.move(to: pt(186.206, 2.08846))
        path.addLine(to: pt(361.863, 177.771))
        path.addCurve(to: pt(354.396, 189.513), control1: pt(367.259, 183.167), control2: pt(361.569, 192.128))
        path.addCurve(to: pt(181.165, 155.993), control1: pt(316.632, 175.765), control2: pt(250.306, 155.993))
        path.addCurve(to: pt(9.71505, 187.802), control1: pt(107.77, 155.993), control2: pt(45.814, 174.184))
        path.addCurve(to: pt(2.18628, 186.239), control1: pt(6.73763, 188.926), control2: pt(3.98869, 188.041))
        path.addCurve(to: pt(2.13914, 176.099), control1: pt(-0.370452, 183.682), control2: pt(-1.04862, 179.286))
        path.addLine(to: pt(176.12, 2.09207))
        path.addCurve(to: pt(186.206, 2.08846), control1: pt(178.909, -0.696765), control2: pt(183.424, -0.696746))
        path.closeSubpath()
        return path
    }
}

#Preview {
    BFArrowMark()
        .fill(BFColor.primary)
        .frame(width: 88, height: 46)
        .padding()
}
