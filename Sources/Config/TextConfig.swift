import Domain
import SwiftUI

// MARK: - TextConfig

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

extension TextConfig: Sendable {}

// MARK: - DecodeEffectConfig

public struct DecodeEffectConfig: Sendable {
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

extension DecodeEffectConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case duration, charset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = try c.flexibleDouble(forKey: .duration) ?? 0.8
        if let arr = try? c.decodeIfPresent([CharsetName].self, forKey: .charset) {
            charset = Set(arr)
        } else if let single = try? c.decodeIfPresent(CharsetName.self, forKey: .charset) {
            charset = [single]
        } else {
            charset = Set(CharsetName.allCases)
        }
    }
}

// MARK: - Layer defaults

private let defaultDefaults = TextStyleConfig(
    font: nil, size: 12, weight: "regular",
    color: .solid("#FFFFFFD9"), shadow: "#000000E6", spacing: 6
)

private let titleDefaults = TextStyleConfig(size: 18, weight: "bold")
private let artistDefaults = TextStyleConfig(weight: "medium")
private let highlightDefaults = TextStyleConfig(
    color: .gradient(["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"])
)

// MARK: - Resolution

extension TextConfig {
    private var resolvedDefault: TextStyleConfig {
        `default`.filled(with: defaultDefaults)
    }

    @MainActor var resolvedTitle: ResolvedTextStyle {
        (title ?? .init()).filled(with: titleDefaults).filled(with: resolvedDefault).resolve()
    }

    @MainActor var resolvedArtist: ResolvedTextStyle {
        (artist ?? .init()).filled(with: artistDefaults).filled(with: resolvedDefault).resolve()
    }

    @MainActor var resolvedLyric: ResolvedTextStyle {
        (lyric ?? .init()).filled(with: resolvedDefault).resolve()
    }

    @MainActor var resolvedHighlight: ResolvedTextStyle {
        (highlight ?? .init())
            .filled(with: highlightDefaults)
            .filled(with: (lyric ?? .init()))
            .filled(with: resolvedDefault)
            .resolve()
    }
}

extension TextStyleConfig {
    @MainActor
    func resolve() -> ResolvedTextStyle {
        let fontName = font ?? NSFont.systemFont(ofSize: 0).familyName ?? ".AppleSystemUIFont"
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
