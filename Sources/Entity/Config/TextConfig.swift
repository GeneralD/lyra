import Foundation

public struct TextConfig {
    public let `default`: TextAppearanceConfig
    public let title: TextAppearanceConfig
    public let artist: TextAppearanceConfig
    public let lyric: TextAppearanceConfig
    public let highlight: TextAppearanceConfig
    public let decodeEffect: DecodeEffectConfig
}

extension TextConfig: Sendable {}

extension TextConfig {
    static let defaults = resolve()

    fileprivate static func resolve(
        default unresolvedDefault: UnresolvedTextAppearance? = nil,
        title unresolvedTitle: UnresolvedTextAppearance? = nil,
        artist unresolvedArtist: UnresolvedTextAppearance? = nil,
        lyric unresolvedLyric: UnresolvedTextAppearance? = nil,
        highlight unresolvedHighlight: UnresolvedTextAppearance? = nil,
        decodeEffect: DecodeEffectConfig = .defaults
    ) -> TextConfig {
        let base = unresolvedDefault.resolve(defaults: .defaults, filled: .defaults)
        let title = unresolvedTitle.resolve(defaults: .titleDefaults, filled: base)
        let artist = unresolvedArtist.resolve(defaults: .artistDefaults, filled: base)
        let lyric = unresolvedLyric.resolve(filled: base)
        let highlight = unresolvedHighlight.resolve(defaults: .highlightDefaults, filled: lyric)
        return TextConfig(default: base, title: title, artist: artist, lyric: lyric, highlight: highlight, decodeEffect: decodeEffect)
    }
}

extension TextConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case `default`, title, artist, lyric, highlight
        case decodeEffect = "decode_effect"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = Self.resolve(
            default: try c.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .default),
            title: try c.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .title),
            artist: try c.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .artist),
            lyric: try c.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .lyric),
            highlight: try c.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .highlight),
            decodeEffect: try c.decodeIfPresent(DecodeEffectConfig.self, forKey: .decodeEffect) ?? .defaults
        )
    }
}

// MARK: - Private: UnresolvedTextAppearance

private struct UnresolvedTextAppearance: Codable {
    var fontName: String?
    var fontSize: FlexibleDouble?
    var fontWeight: String?
    var color: ColorStyle?
    var shadow: ColorStyle?
    var spacing: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case fontName = "font"
        case fontSize = "size"
        case fontWeight = "weight"
        case color, shadow, spacing
    }
}

extension UnresolvedTextAppearance {
    fileprivate static let defaults = UnresolvedTextAppearance(
        fontName: "Helvetica Neue", fontSize: 12.0, fontWeight: "regular",
        color: .solid("#FFFFFFD9"), shadow: .solid("#000000E6"), spacing: 6.0
    )

    fileprivate static let titleDefaults = UnresolvedTextAppearance(fontSize: 18.0, fontWeight: "bold")
    fileprivate static let artistDefaults = UnresolvedTextAppearance(fontWeight: "medium")
    fileprivate static let highlightDefaults = UnresolvedTextAppearance(
        color: .gradient(["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"])
    )

    fileprivate func resolve(defaults: UnresolvedTextAppearance..., filled: TextAppearanceConfig) -> TextAppearanceConfig {
        resolve(defaults: defaults, filled: filled)
    }

    fileprivate func resolve(defaults: [UnresolvedTextAppearance], filled: TextAppearanceConfig) -> TextAppearanceConfig {
        guard let first = defaults.first else {
            return TextAppearanceConfig(
                fontName: fontName ?? filled.fontName,
                fontSize: fontSize?.value ?? filled.fontSize,
                fontWeight: fontWeight ?? filled.fontWeight,
                color: color ?? filled.color,
                shadow: shadow ?? filled.shadow,
                spacing: spacing?.value ?? filled.spacing
            )
        }
        let merged = UnresolvedTextAppearance(
            fontName: fontName ?? first.fontName,
            fontSize: fontSize ?? first.fontSize,
            fontWeight: fontWeight ?? first.fontWeight,
            color: color ?? first.color,
            shadow: shadow ?? first.shadow,
            spacing: spacing ?? first.spacing
        )
        return merged.resolve(defaults: Array(defaults.dropFirst()), filled: filled)
    }
}

extension Optional where Wrapped == UnresolvedTextAppearance {
    fileprivate func resolve(defaults: UnresolvedTextAppearance..., filled: TextAppearanceConfig) -> TextAppearanceConfig {
        (self ?? .init()).resolve(defaults: defaults, filled: filled)
    }
}
