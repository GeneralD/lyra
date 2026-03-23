import Domain
import SwiftUI

public func parseHexColor(_ hex: String) -> Color {
    let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
    guard let value = UInt64(h, radix: 16) else { return .white }
    switch h.count {
    case 3:
        return Color(
            red: Double((value >> 8) & 0xF) / 15,
            green: Double((value >> 4) & 0xF) / 15,
            blue: Double(value & 0xF) / 15
        )
    case 6:
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    case 8:
        return Color(
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            opacity: Double(value & 0xFF) / 255
        )
    default:
        return .white
    }
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
