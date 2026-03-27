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

public struct RippleStyle {
    public let enabled: Bool
    public let color: ColorStyle
    public let radius: Double
    public let duration: Double
    public let idle: Double

    public init(
        enabled: Bool = true,
        color: ColorStyle = .solid("#AAAAFFFF"),
        radius: Double = 60,
        duration: Double = 0.6,
        idle: Double = 1
    ) {
        self.enabled = enabled
        self.color = color
        self.radius = radius
        self.duration = duration
        self.idle = idle
    }
}

extension RippleStyle: Sendable {}