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

public struct TextLayout {
    public let title: TextAppearance
    public let artist: TextAppearance
    public let lyric: TextAppearance
    public let highlight: TextAppearance
    public let decodeEffect: DecodeEffect

    public init(
        title: TextAppearance = .init(fontSize: 18, fontWeight: "bold"),
        artist: TextAppearance = .init(fontWeight: "medium"),
        lyric: TextAppearance = .init(),
        highlight: TextAppearance = .init(),
        decodeEffect: DecodeEffect = .init()
    ) {
        self.title = title
        self.artist = artist
        self.lyric = lyric
        self.highlight = highlight
        self.decodeEffect = decodeEffect
    }
}

extension TextLayout: Sendable {}