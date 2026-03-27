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

public struct DecodeEffectConfig {
    public let duration: FlexibleDouble
    public let charset: Set<CharsetName>
}

extension DecodeEffectConfig: Sendable {}

extension DecodeEffectConfig {
    static let defaults = DecodeEffectConfig(duration: 0.8, charset: Set(CharsetName.allCases))
}

extension DecodeEffectConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decodeIfPresent(FlexibleDouble.self, forKey: .duration) ?? Self.defaults.duration
        switch (
            try? container.decodeIfPresent([CharsetName].self, forKey: .charset), try? container.decodeIfPresent(CharsetName.self, forKey: .charset)
        ) {
        case (.some(let arr), _):
            charset = Set(arr)
        case (_, .some(let single)):
            charset = [single]
        default:
            charset = Self.defaults.charset
        }
    }
}