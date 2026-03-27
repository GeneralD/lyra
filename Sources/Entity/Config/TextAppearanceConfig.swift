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

public struct TextAppearanceConfig {
    public let fontName: String
    public let fontSize: Double
    public let fontWeight: String
    public let color: ColorStyle
    public let shadow: ColorStyle
    public let spacing: Double
}

extension TextAppearanceConfig: Sendable {}
extension TextAppearanceConfig: Codable {}

extension TextAppearanceConfig {
    static let defaults = TextAppearanceConfig(
        fontName: "Helvetica Neue", fontSize: 12, fontWeight: "regular",
        color: .solid("#FFFFFFD9"), shadow: .solid("#000000E6"), spacing: 6
    )
}