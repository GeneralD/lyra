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

public struct RippleConfig {
    public let enabled: Bool
    public let color: String
    public let radius: FlexibleDouble
    public let duration: FlexibleDouble
    public let idle: FlexibleDouble
}

extension RippleConfig: Sendable {}

extension RippleConfig {
    static let defaults = RippleConfig(enabled: true, color: "#AAAAFFFF", radius: 60, duration: 0.6, idle: 1)
}

extension RippleConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.defaults.enabled
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? Self.defaults.color
        radius = try container.decodeIfPresent(FlexibleDouble.self, forKey: .radius) ?? Self.defaults.radius
        duration = try container.decodeIfPresent(FlexibleDouble.self, forKey: .duration) ?? Self.defaults.duration
        idle = try container.decodeIfPresent(FlexibleDouble.self, forKey: .idle) ?? Self.defaults.idle
    }
}