// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
        let style = isActive ? highlightStyle : lyricStyle

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