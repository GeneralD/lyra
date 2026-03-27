import Dependencies
import Domain
import SwiftUI

@MainActor
public struct LyricLineView: View {
    let text: String
    let isActive: Bool
    let lyricStyle: TextAppearance
    let highlightStyle: TextAppearance

    public init(text: String, isActive: Bool, lyricStyle: TextAppearance, highlightStyle: TextAppearance) {
        self.text = text
        self.isActive = isActive
        self.lyricStyle = lyricStyle
        self.highlightStyle = highlightStyle
    }

    public var body: some View {
        @Dependency(\.swiftUIResolver) var resolver
        let style = isActive ? highlightStyle : lyricStyle

        Text(text.isEmpty ? " " : text)
            .font(resolver.font(from: style))
            .foregroundStyle(resolver.shapeStyle(from: style.color))
            .opacity(isActive ? 1.0 : 0.7)
            .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
            .shadow(color: resolver.solidColor(from: style.shadow), radius: 5, x: 0, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, style.spacing)
            .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

#if DEBUG
    #Preview("Normal") {
        LyricLineView(
            text: "It been a long day without you my friend",
            isActive: false, lyricStyle: .init(), highlightStyle: .init()
        )
        .padding()
        .background(.black)
    }

    #Preview("Active") {
        LyricLineView(
            text: "It been a long day without you my friend",
            isActive: true, lyricStyle: .init(), highlightStyle: .init()
        )
        .padding()
        .background(.black)
    }
#endif
