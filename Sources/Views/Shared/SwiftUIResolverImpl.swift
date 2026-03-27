import Dependencies
import Domain
import SwiftUI

// MARK: - ColorConfig → SwiftUI

extension ColorConfig {
    fileprivate var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}

extension ColorStyle {
    fileprivate var firstConfig: ColorConfig {
        switch self {
        case .solid(let config): config
        case .gradient(let configs): configs.first ?? .white
        }
    }
}

// MARK: - Live Implementation

public struct SwiftUIResolverImpl: SwiftUIResolver {
    public init() {}

    @MainActor public func font(from style: TextAppearance) -> Font {
        let weight: Font.Weight =
            switch style.fontWeight.lowercased() {
            case "ultralight": .ultraLight
            case "thin": .thin
            case "light": .light
            case "medium": .medium
            case "semibold": .semibold
            case "bold": .bold
            case "heavy": .heavy
            case "black": .black
            default: .regular
            }
        return Font.custom(style.fontName, size: style.fontSize).weight(weight)
    }

    @MainActor public func color(from hex: String) -> Color {
        ColorConfig(hex: hex).color
    }

    @MainActor public func solidColor(from style: ColorStyle) -> Color {
        style.firstConfig.color
    }

    @MainActor public func shapeStyle(from style: ColorStyle) -> AnyShapeStyle {
        switch style {
        case .solid(let config):
            return AnyShapeStyle(config.color)
        case .gradient(let configs):
            let colors = configs.map(\.color)
            guard colors.count > 1 else {
                return .init(colors.first ?? .white)
            }
            let stops = colors.enumerated().map { i, c in
                Gradient.Stop(color: c, location: CGFloat(i) / CGFloat(colors.count - 1))
            }
            return .init(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
        }
    }

    @MainActor public func color(
        _ style: ColorStyle, hueShiftedBy shift: Double, opacity: Double
    ) -> Color {
        let hsb = style.firstConfig.hsb
        return Color(
            hue: (hsb.hue + shift).truncatingRemainder(dividingBy: 1),
            saturation: hsb.saturation,
            brightness: hsb.brightness,
            opacity: opacity
        )
    }

    @MainActor public func hsbComponents(
        from style: ColorStyle
    ) -> (hue: Double, saturation: Double, brightness: Double) {
        style.firstConfig.hsb
    }

    @MainActor public func lineHeight(from style: TextAppearance) -> Double {
        @Dependency(\.fontMetrics) var fontMetrics
        return fontMetrics.lineHeight(
            fontName: style.fontName, fontSize: style.fontSize, spacing: style.spacing
        )
    }
}
