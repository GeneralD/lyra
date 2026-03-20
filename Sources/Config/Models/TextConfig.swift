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
    static let defaults = TextConfig(
        default: .defaults, title: .defaults, artist: .defaults, lyric: .defaults, highlight: .defaults,
        decodeEffect: .defaults
    )
}

extension TextConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case `default`, title, artist, lyric, highlight
        case decodeEffect = "decode_effect"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let unresolvedDefault = try container.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .default)
        let unresolvedTitle = try container.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .title)
        let unresolvedArtist = try container.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .artist)
        let unresolvedLyric = try container.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .lyric)
        let unresolvedHighlight = try container.decodeIfPresent(UnresolvedTextAppearance.self, forKey: .highlight)

        `default` = unresolvedDefault.resolve(defaults: .defaults, filled: .defaults)
        title = unresolvedTitle.resolve(defaults: .titleDefaults, filled: `default`)
        artist = unresolvedArtist.resolve(defaults: .artistDefaults, filled: `default`)
        lyric = unresolvedLyric.resolve(filled: `default`)
        highlight = unresolvedHighlight.resolve(defaults: .highlightDefaults, filled: lyric)

        decodeEffect = try container.decodeIfPresent(DecodeEffectConfig.self, forKey: .decodeEffect) ?? .defaults
    }
}
