import Domain
import Dependencies
import SwiftUI

@MainActor
public struct LyricLineView: View {
    let text: String
    let isActive: Bool

    @Dependency(\.appStyle) private var config

    public init(text: String, isActive: Bool) {
        self.text = text
        self.isActive = isActive
    }

    public var body: some View {
        let style = isActive ? config.text.highlight : config.text.lyric

        Text(text.isEmpty ? " " : text)
            .font(makeFont(style: style))
            .foregroundStyle(style.color.shapeStyle)
            .opacity(isActive ? 1.0 : 0.7)
            .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
            .shadow(color: style.shadow.solidColor, radius: 5, x: 0, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, style.spacing)
            .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

func makeFont(style: TextAppearance) -> Font {
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


#if DEBUG
#Preview("Normal") {
    withDependencies { $0.appStyle = .init() } operation: {
        LyricLineView(text: "It been a long day without you my friend", isActive: false)
            .padding()
            .background(.black)
    }
}

#Preview("Active") {
    withDependencies { $0.appStyle = .init() } operation: {
        LyricLineView(text: "It been a long day without you my friend", isActive: true)
            .padding()
            .background(.black)
    }
}
#endif
