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

import Foundation

public struct AppConfig {
    public let text: TextConfig
    public let artwork: ArtworkConfig
    public let ripple: RippleConfig
    public let screen: ScreenSelector
    public let wallpaper: WallpaperConfig?
    public let ai: AIConfig?
}

extension AppConfig: Sendable {}

extension AppConfig {
    public static let defaults = AppConfig(text: .defaults, artwork: .defaults, ripple: .defaults, screen: .main, wallpaper: nil, ai: nil)
}

extension AppConfig: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(TextConfig.self, forKey: .text) ?? Self.defaults.text
        artwork = try c.decodeIfPresent(ArtworkConfig.self, forKey: .artwork) ?? Self.defaults.artwork
        ripple = try c.decodeIfPresent(RippleConfig.self, forKey: .ripple) ?? Self.defaults.ripple
        screen = try c.decodeIfPresent(ScreenSelector.self, forKey: .screen) ?? Self.defaults.screen
        wallpaper = try c.decodeIfPresent(WallpaperConfig.self, forKey: .wallpaper) ?? Self.defaults.wallpaper
        ai = try? c.decodeIfPresent(AIConfig.self, forKey: .ai) ?? Self.defaults.ai
    }
}