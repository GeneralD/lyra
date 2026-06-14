public struct DecodeEffectConfig {
    public let duration: FlexibleDouble
    public let charset: Set<CharsetName>
    public let processingColor: ColorStyle
}

extension DecodeEffectConfig: Sendable {}

extension DecodeEffectConfig {
    static let defaults = DecodeEffectConfig(
        duration: 0.8, charset: Set(CharsetName.allCases), processingColor: .solid("#4ADE80FF"))
}

extension DecodeEffectConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case duration, charset
        case processingColor = "processing_color"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decodeIfPresent(FlexibleDouble.self, forKey: .duration) ?? Self.defaults.duration
        processingColor =
            try container.decodeIfPresent(ColorStyle.self, forKey: .processingColor) ?? Self.defaults.processingColor
        switch (
            try? container.decodeIfPresent([CharsetName].self, forKey: .charset), try? container.decodeIfPresent(CharsetName.self, forKey: .charset)
        ) {
        case (.some(let arr), _):
            charset = Set(arr)
        case (_, .some(let single)):
            charset = [single]
        default:
            charset = Self.defaults.charset
        }
    }
}
