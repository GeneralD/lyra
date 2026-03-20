import Domain
import Dependencies
import Foundation
import TOMLKit

// MARK: - AppConfig

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
        text = try c.decodeIfPresent(TextConfig.self, forKey: .text) ?? .init()
        artwork = try c.decodeIfPresent(ArtworkConfig.self, forKey: .artwork) ?? .init()
        ripple = try c.decodeIfPresent(RippleConfig.self, forKey: .ripple) ?? .init()
        screen = try c.decodeIfPresent(ScreenSelector.self, forKey: .screen) ?? .main
        wallpaper = try c.decodeIfPresent(String.self, forKey: .wallpaper)
        ai = try? c.decodeIfPresent(AIConfig.self, forKey: .ai)
        configDir = nil
    }

    init(
        text: TextConfig = .init(),
        artwork: ArtworkConfig = .init(),
        ripple: RippleConfig = .init(),
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

// MARK: - Wallpaper URL

extension AppConfig {
    public var wallpaperURL: URL? {
        guard let wallpaper else { return nil }
        guard !wallpaper.hasPrefix("/") else { return URL(fileURLWithPath: wallpaper) }
        return configDir.map { URL(fileURLWithPath: $0).appendingPathComponent(wallpaper) }
    }
}

// MARK: - Load

extension AppConfig {
    public static func load() -> AppConfig {
        let home = NSHomeDirectory()
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
        let candidates = [
            "\(xdgConfig)/lyra/config.toml",
            "\(home)/.lyra/config.toml",
            "\(xdgConfig)/lyra/config.json",
            "\(home)/.lyra/config.json",
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let content = try? String(contentsOfFile: path, encoding: .utf8)
        else { return .init() }

        let configDir = (path as NSString).deletingLastPathComponent
        let decoded: AppConfig?
        if path.hasSuffix(".toml") {
            do {
                let table = try TOMLTable(string: content)
                resolveIncludes(into: table, configDir: configDir)
                table.remove(at: "includes")
                decoded = try TOMLDecoder().decode(AppConfig.self, from: table)
            } catch {
                notifyConfigError(path: path, error: error)
                decoded = nil
            }
        } else {
            do {
                decoded = try JSONDecoder().decode(AppConfig.self, from: content.data(using: .utf8) ?? Data())
            } catch {
                notifyConfigError(path: path, error: error)
                decoded = nil
            }
        }
        guard let decoded else { return .init() }
        return AppConfig(
            text: decoded.text, artwork: decoded.artwork, ripple: decoded.ripple,
            screen: decoded.screen, wallpaper: decoded.wallpaper,
            configDir: configDir,
            ai: decoded.ai
        )
    }
}

// MARK: - Resolve to Domain types

extension AppConfig {
    @MainActor
    public func toResolvedConfig() -> ResolvedConfig {
        ResolvedConfig(
            text: ResolvedTextConfig(
                title: text.resolvedTitle,
                artist: text.resolvedArtist,
                lyric: text.resolvedLyric,
                highlight: text.resolvedHighlight,
                decodeEffect: ResolvedDecodeEffectConfig(
                    duration: text.decodeEffect.duration,
                    charsets: text.decodeEffect.charset
                )
            ),
            artwork: ResolvedArtworkConfig(size: artwork.size, opacity: artwork.opacity),
            ripple: ResolvedRippleConfig(
                enabled: ripple.enabled,
                color: .solid(ripple.color),
                radius: ripple.radius,
                duration: ripple.duration,
                idle: ripple.idle
            ),
            screen: screen,
            wallpaperURL: wallpaperURL,
            ai: ai.map { ResolvedAIConfig(endpoint: $0.endpoint, model: $0.model, apiKey: $0.apiKey) }
        )
    }
}

// MARK: - DependencyKey registration

extension ConfigKey: DependencyKey {
    public static let liveValue: ResolvedConfig = MainActor.assumeIsolated {
        AppConfig.load().toResolvedConfig()
    }
}
