import BackdropDomain
import Dependencies
import Foundation
import SwiftUI
import TOMLKit

// MARK: - Codable Config Models

public struct TextConfig {
    public let `default`: TextStyleConfig
    public let title: TextStyleConfig?
    public let artist: TextStyleConfig?
    public let lyric: TextStyleConfig?
    public let highlight: TextStyleConfig?
    public let decodeEffect: DecodeEffectConfig

    public init(
        `default`: TextStyleConfig = .init(),
        title: TextStyleConfig? = nil,
        artist: TextStyleConfig? = nil,
        lyric: TextStyleConfig? = nil,
        highlight: TextStyleConfig? = nil,
        decodeEffect: DecodeEffectConfig = .init()
    ) {
        self.default = `default`
        self.title = title
        self.artist = artist
        self.lyric = lyric
        self.highlight = highlight
        self.decodeEffect = decodeEffect
    }
}

extension TextConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case `default`, title, artist, lyric, highlight
        case decodeEffect = "decode_effect"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        `default` = try c.decodeIfPresent(TextStyleConfig.self, forKey: .default) ?? .init()
        title = try c.decodeIfPresent(TextStyleConfig.self, forKey: .title)
        artist = try c.decodeIfPresent(TextStyleConfig.self, forKey: .artist)
        lyric = try c.decodeIfPresent(TextStyleConfig.self, forKey: .lyric)
        highlight = try c.decodeIfPresent(TextStyleConfig.self, forKey: .highlight)
        decodeEffect = try c.decodeIfPresent(DecodeEffectConfig.self, forKey: .decodeEffect) ?? .init()
    }
}

public struct DecodeEffectConfig {
    public let duration: Double
    public let charset: Set<CharsetName>

    public init(
        duration: Double = 0.8,
        charset: Set<CharsetName> = Set(CharsetName.allCases)
    ) {
        self.duration = duration
        self.charset = charset
    }
}

extension DecodeEffectConfig: Sendable {}

extension DecodeEffectConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case duration, charset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = try c.flexibleDouble(forKey: .duration) ?? 0.8
        // Polymorphic: "latin" or ["latin", "cyrillic"]
        if let arr = try? c.decodeIfPresent([CharsetName].self, forKey: .charset) {
            charset = Set(arr)
        } else if let single = try? c.decodeIfPresent(CharsetName.self, forKey: .charset) {
            charset = [single]
        } else {
            charset = Set(CharsetName.allCases)
        }
    }
}

extension TextConfig {
    @MainActor var resolvedTitle: ResolvedTextStyle {
        (title ?? .init())
            .merging(over: TextStyleConfig(size: 18, weight: "bold").merging(over: `default`))
            .resolve()
    }

    @MainActor var resolvedArtist: ResolvedTextStyle {
        (artist ?? .init())
            .merging(over: TextStyleConfig(weight: "medium").merging(over: `default`))
            .resolve()
    }

    @MainActor var resolvedLyric: ResolvedTextStyle {
        (lyric ?? .init()).merging(over: `default`).resolve()
    }

    private static let highlightDefaults = TextStyleConfig(
        color: .gradient(["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"])
    )

    @MainActor var resolvedHighlight: ResolvedTextStyle {
        (highlight ?? .init())
            .merging(over: Self.highlightDefaults.merging(over: (lyric ?? .init()).merging(over: `default`)))
            .resolve()
    }
}

public struct ArtworkConfig {
    public let size: CGFloat
    public let opacity: Double

    public init(size: CGFloat = 96, opacity: Double = 1.0) {
        self.size = size
        self.opacity = opacity
    }
}

extension ArtworkConfig: Codable {
    enum CodingKeys: String, CodingKey { case size, opacity }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.flexibleDoubleRequired(forKey: .size)
        opacity = try c.flexibleDouble(forKey: .opacity) ?? 1.0
    }
}

public struct RippleConfig {
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

extension RippleConfig: Codable {
    enum CodingKeys: String, CodingKey { case color, radius, duration, idle }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decode(String.self, forKey: .color)
        radius = try c.flexibleDoubleRequired(forKey: .radius)
        duration = try c.flexibleDoubleRequired(forKey: .duration)
        idle = try c.flexibleDoubleRequired(forKey: .idle)
    }
}

// MARK: - AppConfig

public struct AppConfig: Codable {
    public let text: TextConfig
    public let artwork: ArtworkConfig
    public let ripple: RippleConfig
    public let screen: ScreenSelector
    public let wallpaper: String?
    public let configDir: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(TextConfig.self, forKey: .text) ?? .init()
        artwork = try c.decodeIfPresent(ArtworkConfig.self, forKey: .artwork) ?? .init()
        ripple = try c.decodeIfPresent(RippleConfig.self, forKey: .ripple) ?? .init()
        screen = try c.decodeIfPresent(ScreenSelector.self, forKey: .screen) ?? .main
        wallpaper = try c.decodeIfPresent(String.self, forKey: .wallpaper)
        configDir = nil
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
}

extension AppConfig {
    public var wallpaperURL: URL? {
        guard let wallpaper else { return nil }
        guard !wallpaper.hasPrefix("/") else { return URL(fileURLWithPath: wallpaper) }
        return configDir.map { URL(fileURLWithPath: $0).appendingPathComponent(wallpaper) }
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
            do {
                decoded = try TOMLDecoder().decode(AppConfig.self, from: content)
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
                highlight: text.resolvedHighlight,
                decodeEffect: ResolvedDecodeEffectConfig(
                    duration: text.decodeEffect.duration,
                    charsets: text.decodeEffect.charset
                )
            ),
            artwork: ResolvedArtworkConfig(size: artwork.size, opacity: artwork.opacity),
            ripple: ResolvedRippleConfig(
                color: .solid(ripple.color),
                radius: ripple.radius,
                duration: ripple.duration,
                idle: ripple.idle
            ),
            screen: screen,
            wallpaperURL: wallpaperURL
        )
    }
}

extension TextStyleConfig {
    @MainActor
    func resolve() -> ResolvedTextStyle {
        let fontName = font ?? "Zen Maru Gothic"
        let fontSize = size ?? 12
        let fontWeight = weight ?? "regular"
        let spacing = spacing ?? 6

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
            color: color ?? .solid("#FFFFFFD9"),
            shadow: .solid(shadow ?? "#000000E6"),
            lineHeight: lineHeight
        )
    }
}

// MARK: - Config error notification

private func notifyConfigError(path: String, error: Error) {
    fputs("backdrop: failed to decode \(path): \(error)\n", stderr)
    @Dependency(\.userNotifier) var notifier
    notifier.notify(
        title: "backdrop",
        subtitle: "Config error: \((path as NSString).lastPathComponent)",
        message: String(describing: error),
        fileToOpen: path
    )
}

// MARK: - DependencyKey registration

extension ConfigKey: DependencyKey {
    public static let liveValue: ResolvedConfig = MainActor.assumeIsolated {
        AppConfig.load().toResolvedConfig()
    }
}

extension TextConfig: Sendable {}
extension ArtworkConfig: Sendable {}
extension RippleConfig: Sendable {}
extension AppConfig: Sendable {}
