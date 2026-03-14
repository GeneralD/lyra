import BackdropConfig
import BackdropDomain
import Dependencies
import SwiftUI

@MainActor
public struct LyricLineView: View {
    let text: String
    let isActive: Bool

    @Dependency(\.config) private var config

    public init(text: String, isActive: Bool) {
        self.text = text
        self.isActive = isActive
    }

    public var body: some View {
        let style = config.text.lyric
        let highlightStyle = makeHighlightStyle(from: config.text.highlightColors)
        let swiftFont = makeFont(style: style)
        let swiftColor = parseHexColor(style.colorHex)
        let swiftShadow = parseHexColor(style.shadowHex)

        Text(text.isEmpty ? " " : text)
            .font(swiftFont)
            .foregroundStyle(isActive ? highlightStyle : .init(swiftColor))
            .opacity(isActive ? 1.0 : 0.7)
            .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
            .shadow(color: swiftShadow, radius: 5, x: 0, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, style.spacing)
            .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

func makeFont(style: ResolvedTextStyle) -> Font {
    let weight: Font.Weight = switch style.fontWeight.lowercased() {
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

func makeHighlightStyle(from hexColors: [String]) -> AnyShapeStyle {
    let colors = hexColors.map(parseHexColor)
    guard colors.count > 1 else {
        return .init(colors.first ?? .white)
    }
    let stops = colors.enumerated().map { i, color in
        Gradient.Stop(color: color, location: CGFloat(i) / CGFloat(colors.count - 1))
    }
    return .init(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
}
