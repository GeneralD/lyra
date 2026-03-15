import BackdropConfig
import BackdropDomain
import Dependencies
import SwiftUI

/// Declarative text view driven by FetchState.
/// .idle → nothing, .loading → flickering, .revealing → decode animation, .success → static text, .failure → empty
@MainActor
public struct DecodeTextView: View {
    let fetchState: FetchState<String>
    let style: ResolvedTextStyle

    @State private var effectState: DecodeEffectState

    public init(fetchState: FetchState<String>, style: ResolvedTextStyle) {
        self.fetchState = fetchState
        self.style = style
        @Dependency(\.config) var config
        _effectState = State(initialValue: DecodeEffectState(config: config.text.decodeEffect))
    }

    public var body: some View {
        Text(effectState.displayText.isEmpty ? " " : effectState.displayText)
            .font(makeFont(style: style))
            .foregroundStyle(style.color.shapeStyle)
            .shadow(color: style.shadow.solidColor, radius: 5, x: 0, y: 1)
            .lineLimit(1)
            .onAppear { apply(fetchState) }
            .onChange(of: fetchState) { _, newState in apply(newState) }
    }

    private func apply(_ state: FetchState<String>) {
        switch state {
        case .idle, .failure:
            effectState.set("")
        case .loading:
            effectState.startLoading()
        case .revealing(let text):
            effectState.decode(to: text)
        case .success(let text):
            effectState.set(text)
        }
    }
}
