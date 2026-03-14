import BackdropDomain
import Dependencies
import Foundation
import SwiftUI
import TOMLKit

// MARK: - Codable Config Models

public struct TextConfig: Codable, Sendable {
    public let `default`: TextStyleConfig
    public let title: TextStyleConfig?
    public let artist: TextStyleConfig?
    public let lyric: TextStyleConfig?
    public let highlight: [String]

    private static let titleDefaults: TextStyleConfig = .init(size: 18, weight: "bold")
    private static let artistDefaults: TextStyleConfig = .init(weight: "medium")

    @MainActor
    public var resolvedTitle: ResolvedTextStyle {
        resolveStyle((title ?? .init()).merging(over: Self.titleDefaults.merging(over: `default`)))
    }

    @MainActor
    public var resolvedArtist: ResolvedTextStyle {
        resolveStyle((artist ?? .init()).merging(over: Self.artistDefaults.merging(over: `default`)))
    }

    @MainActor
    public var resolvedLyric: ResolvedTextStyle {
        resolveStyle((lyric ?? .init()).merging(over: `default`))
    }

    public init(
        `default`: TextStyleConfig = .init(),
        title: TextStyleConfig? = nil,
        artist: TextStyleConfig? = nil,
        lyric: TextStyleConfig? = nil,
        highlight: [String] = ["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"]
    ) {
        self.default = `default`
        self.title = title
        self.artist = artist
        self.lyric = lyric
        self.highlight = highlight
    }

    enum CodingKeys: String, CodingKey {
        case `default`, title, artist, lyric, highlight
    }
}

public struct ArtworkConfig: Codable, Sendable {
    public let size: CGFloat

    public init(size: CGFloat = 96) { self.size = size }
}

public struct RippleConfig: Codable, Sendable {
    public let color: String
    public let radius: Double
    public let duration: Double
    public let idle: Double

    public init(color: String = "#AAAAFFFF", radius: Double = 60, duration: Double = 0.6, idle: Double = 1) {
        self.color = color
        self.radius = radius
        self.duration = duration
        self.idle = idle
    }
}

// MARK: - AppConfig (raw Codable)

public struct AppConfig: Codable, Sendable {
    public let text: TextConfig
    public let artwork: ArtworkConfig
    public let ripple: RippleConfig
    public let screen: ScreenSelector
    public let wallpaper: String?
    public let configDir: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(TextConfig.self, forKey: .text) ?? .init()
        artwork = try container.decodeIfPresent(ArtworkConfig.self, forKey: .artwork) ?? .init()
        ripple = try container.decodeIfPresent(RippleConfig.self, forKey: .ripple) ?? .init()
        screen = try container.decodeIfPresent(ScreenSelector.self, forKey: .screen) ?? .main
        wallpaper = try container.decodeIfPresent(String.self, forKey: .wallpaper)
        configDir = nil
    }

    public var wallpaperURL: URL? {
        guard let wallpaper else { return nil }
        guard !wallpaper.hasPrefix("/") else { return URL(fileURLWithPath: wallpaper) }
        return configDir.map { URL(fileURLWithPath: $0).appendingPathComponent(wallpaper) }
    }

    public init(
        text: TextConfig = .init(),
        artwork: ArtworkConfig = .init(),
        ripple: RippleConfig = .init(),
        screen: ScreenSelector = .main,
        wallpaper: String? = nil,
        configDir: String? = nil
    ) {
        self.text = text
        self.artwork = artwork
        self.ripple = ripple
        self.screen = screen
        self.wallpaper = wallpaper
        self.configDir = configDir
    }

    enum CodingKeys: String, CodingKey {
        case text, artwork, ripple, screen, wallpaper
    }

    public static func load() -> AppConfig {
        let home = NSHomeDirectory()
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
        let candidates = [
            "\(xdgConfig)/backdrop/config.toml",
            "\(home)/.backdrop/config.toml",
            "\(xdgConfig)/backdrop/config.json",
            "\(home)/.backdrop/config.json",
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let content = try? String(contentsOfFile: path, encoding: .utf8)
        else { return .init() }

        let decoded: AppConfig?
        if path.hasSuffix(".toml") {
            decoded = try? TOMLDecoder().decode(AppConfig.self, from: content)
        } else {
            decoded = content.data(using: .utf8)
                .flatMap { try? JSONDecoder().decode(AppConfig.self, from: $0) }
        }
        guard let decoded else { return .init() }
        return AppConfig(
            text: decoded.text, artwork: decoded.artwork, ripple: decoded.ripple,
            screen: decoded.screen, wallpaper: decoded.wallpaper,
            configDir: (path as NSString).deletingLastPathComponent
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
                highlightColors: text.highlight
            ),
            artwork: ResolvedArtworkConfig(size: artwork.size),
            ripple: ResolvedRippleConfig(
                colorHex: ripple.color,
                radius: ripple.radius,
                duration: ripple.duration,
                idle: ripple.idle
            ),
            screen: screen,
            wallpaperURL: wallpaperURL
        )
    }
}

@MainActor
private func resolveStyle(_ config: TextStyleConfig) -> ResolvedTextStyle {
    let fontName = config.font ?? "Zen Maru Gothic"
    let fontSize = config.size ?? 12
    let fontWeight = config.weight ?? "regular"
    let spacing = config.spacing ?? 6

    let available = NSFontManager.shared.availableFontFamilies.contains(fontName)
    let nsFont = available ? NSFont(name: fontName, size: fontSize) : nil
    let fallback = NSFont.systemFont(ofSize: fontSize)
    let lineHeight = ceil(
        (nsFont?.ascender ?? fallback.ascender)
            - (nsFont?.descender ?? fallback.descender)
            + (nsFont?.leading ?? fallback.leading)
    ) + spacing * 2

    return ResolvedTextStyle(
        spacing: spacing,
        fontName: fontName,
        fontSize: fontSize,
        fontWeight: fontWeight,
        colorHex: config.color ?? "#FFFFFFD9",
        shadowHex: config.shadow ?? "#000000E6",
        lineHeight: lineHeight
    )
}
