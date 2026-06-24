import SwiftUI

struct BFLogo: View {
    enum Variant: String {
        case full = "LogoFull"
        case short = "LogoShort"
        case symbol = "LogoSymbol"
    }

    enum Size {
        case standard   // 64pt — default app use
        case compact    // 32pt — tab bar / compact
        case minimum    // 16pt — favicon level

        var height: CGFloat {
            switch self {
            case .standard: return 64
            case .compact: return 32
            case .minimum: return 16
            }
        }

        var clearspace: CGFloat {
            switch self {
            case .standard: return 16
            case .compact: return 8
            case .minimum: return 4
            }
        }
    }

    let variant: Variant
    let size: Size

    init(variant: Variant = .full, size: Size = .standard) {
        self.variant = variant
        self.size = size
    }

    var body: some View {
        Image(variant.rawValue)
            .resizable()
            .scaledToFit()
            .frame(height: size.height)
            .padding(size.clearspace)
            .accessibilityLabel("BlueFunda logo")
    }
}
