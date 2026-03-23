import Domain
import SwiftHEXColors
import SwiftUI

public func parseHexColor(_ hex: String) -> Color {
    guard let nsColor = NSColor(hexString: hex) else { return .white }
    return Color(nsColor: nsColor)
}

extension ColorStyle {
    public var shapeStyle: AnyShapeStyle {
        switch self {
        case .solid(let hex):
            return AnyShapeStyle(parseHexColor(hex))
        case .gradient(let hexColors):
            let colors = hexColors.map(parseHexColor)
            guard colors.count > 1 else {
                return .init(colors.first ?? .white)
            }
            let stops = colors.enumerated().map { i, color in
                Gradient.Stop(color: color, location: CGFloat(i) / CGFloat(colors.count - 1))
            }
            return .init(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
        }
    }

    public var solidColor: Color {
        switch self {
        case .solid(let hex): parseHexColor(hex)
        case .gradient(let hexColors): parseHexColor(hexColors.first ?? "#FFFFFF")
        }
    }
}
