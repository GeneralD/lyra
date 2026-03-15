import BackdropConfig
import BackdropDomain
import Dependencies
import SwiftUI

@MainActor
public struct LyricLineView: View {
    let text: String
    let isActive: Bool
    let isRevealing: Bool

    @State private var effectState: DecodeEffectState
    @State private var revealed = false
    @Dependency(\.config) private var config

    public init(text: String, isActive: Bool, isRevealing: Bool) {
        self.text = text
        self.isActive = isActive
        self.isRevealing = isRevealing
        @Dependency(\.config) var config
        _effectState = State(initialValue: DecodeEffectState(config: config.text.decodeEffect))
    }

    public var body: some View {
        let style = isActive ? config.text.highlight : config.text.lyric
        let displayText = revealed ? text : (effectState.displayText.isEmpty ? " " : effectState.displayText)

        Text(displayText)
            .font(makeFont(style: style))
            .foregroundStyle(style.color.shapeStyle)
            .opacity(isActive ? 1.0 : 0.7)
            .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
            .shadow(color: style.shadow.solidColor, radius: 5, x: 0, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, style.spacing)
            .animation(.easeInOut(duration: 0.3), value: isActive)
            .onAppear {
                guard isRevealing, !revealed else {
                    revealed = true
                    effectState.set(text)
                    return
                }
                effectState.decode(to: text)
            }
            .onChange(of: isRevealing) { _, newValue in
                guard !newValue else { return }
                revealed = true
                effectState.set(text)
            }
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
