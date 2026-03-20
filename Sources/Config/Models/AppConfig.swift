import Domain
import Foundation

public struct AppConfig: Sendable {
    public let text: TextConfig
    public let artwork: ArtworkConfig
    public let ripple: RippleConfig
    public let screen: ScreenSelector
    public let wallpaper: String?
    public let ai: AIConfig?
}

extension AppConfig {
    static let defaults = AppConfig(text: .defaults, artwork: .defaults, ripple: .defaults, screen: .main, wallpaper: nil, ai: nil)
}

extension AppConfig: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(TextConfig.self, forKey: .text) ?? Self.defaults.text
        artwork = try c.decodeIfPresent(ArtworkConfig.self, forKey: .artwork) ?? Self.defaults.artwork
        ripple = try c.decodeIfPresent(RippleConfig.self, forKey: .ripple) ?? Self.defaults.ripple
        screen = try c.decodeIfPresent(ScreenSelector.self, forKey: .screen) ?? Self.defaults.screen
        wallpaper = try c.decodeIfPresent(String.self, forKey: .wallpaper) ?? Self.defaults.wallpaper
        ai = try? c.decodeIfPresent(AIConfig.self, forKey: .ai) ?? Self.defaults.ai
    }
}