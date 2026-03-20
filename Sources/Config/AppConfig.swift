import Domain
import Foundation

public struct AppConfig: Sendable, Decodable {
    public let text: TextConfig
    public let artwork: ArtworkConfig
    public let ripple: RippleConfig
    public let screen: ScreenSelector
    public let wallpaper: String?
    public let configDir: String?
    public let ai: AIConfig?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(TextConfig.self, forKey: .text) ?? .defaults
        artwork = try c.decodeIfPresent(ArtworkConfig.self, forKey: .artwork) ?? .defaults
        ripple = try c.decodeIfPresent(RippleConfig.self, forKey: .ripple) ?? .defaults
        screen = try c.decodeIfPresent(ScreenSelector.self, forKey: .screen) ?? .main
        wallpaper = try c.decodeIfPresent(String.self, forKey: .wallpaper)
        ai = try? c.decodeIfPresent(AIConfig.self, forKey: .ai)
        configDir = nil
    }

    init(
        text: TextConfig = .defaults,
        artwork: ArtworkConfig = .defaults,
        ripple: RippleConfig = .defaults,
        screen: ScreenSelector = .main,
        wallpaper: String? = nil,
        configDir: String? = nil,
        ai: AIConfig? = nil
    ) {
        self.text = text
        self.artwork = artwork
        self.ripple = ripple
        self.screen = screen
        self.wallpaper = wallpaper
        self.configDir = configDir
        self.ai = ai
    }

    enum CodingKeys: String, CodingKey {
        case text, artwork, ripple, screen, wallpaper, ai
    }
}

extension AppConfig {
    public var wallpaperURL: URL? {
        guard let wallpaper else { return nil }
        guard !wallpaper.hasPrefix("/") else { return URL(fileURLWithPath: wallpaper) }
        return configDir.map { URL(fileURLWithPath: $0).appendingPathComponent(wallpaper) }
    }
}
