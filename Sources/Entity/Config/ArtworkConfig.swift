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

public struct ArtworkConfig {
    public let size: FlexibleDouble
    public let opacity: FlexibleDouble
}

extension ArtworkConfig: Sendable {}

extension ArtworkConfig {
    static let defaults = ArtworkConfig(size: 96, opacity: 1.0)
}

extension ArtworkConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(FlexibleDouble.self, forKey: .size) ?? Self.defaults.size
        opacity = try container.decodeIfPresent(FlexibleDouble.self, forKey: .opacity) ?? Self.defaults.opacity
    }
}