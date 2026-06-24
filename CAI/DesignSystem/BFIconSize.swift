import SwiftUI

enum BFIconSize: CGFloat {
    case sm = 16
    case md = 20
    case lg = 24
    case xl = 28
    case illustration = 48
}

extension Image {
    func bfIcon(_ size: BFIconSize = .md, color: Color = BFColor.neutral500) -> some View {
        self
            .resizable()
            .scaledToFit()
            .frame(width: size.rawValue, height: size.rawValue)
            .foregroundStyle(color)
    }
}
