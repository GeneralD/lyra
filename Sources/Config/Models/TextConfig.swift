import Domain

public struct TextConfig: Sendable {
    public let `default`: TextAppearanceConfig
    public let title: TextAppearanceConfig
    public let artist: TextAppearanceConfig
    public let lyric: TextAppearanceConfig
    public let highlight: TextAppearanceConfig
    public let decodeEffect: DecodeEffectConfig
}

extension TextConfig {
    static let defaults = resolve()

    static func resolve(
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
