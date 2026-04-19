import Foundation

public struct AppConfig {
    public let text: TextConfig
    public let artwork: ArtworkConfig
    public let ripple: RippleConfig
    public let screen: ScreenSelector
    public let screenDebounce: FlexibleDouble
    public let wallpaper: WallpaperConfig?
    public let ai: AIConfig?
}

extension AppConfig: Sendable {}

extension AppConfig {
    public static let defaults = AppConfig(
        text: .defaults, artwork: .defaults, ripple: .defaults, screen: .main, screenDebounce: 5, wallpaper: nil, ai: nil)
}

extension AppConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case text, artwork, ripple, screen
        case screenDebounce = "screen_debounce"
        case wallpaper, ai
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(TextConfig.self, forKey: .text) ?? Self.defaults.text
        artwork = try c.decodeIfPresent(ArtworkConfig.self, forKey: .artwork) ?? Self.defaults.artwork
        ripple = try c.decodeIfPresent(RippleConfig.self, forKey: .ripple) ?? Self.defaults.ripple
        screen = try c.decodeIfPresent(ScreenSelector.self, forKey: .screen) ?? Self.defaults.screen
        screenDebounce = try c.decodeIfPresent(FlexibleDouble.self, forKey: .screenDebounce) ?? Self.defaults.screenDebounce
        wallpaper = try c.decodeIfPresent(WallpaperConfig.self, forKey: .wallpaper) ?? Self.defaults.wallpaper
        ai = try? c.decodeIfPresent(AIConfig.self, forKey: .ai) ?? Self.defaults.ai
    }
}
