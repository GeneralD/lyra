public struct DecodeEffectConfig {
    public let duration: FlexibleDouble
    public let charset: Set<CharsetName>
}

extension DecodeEffectConfig: Sendable {}

extension DecodeEffectConfig {
    static let defaults = DecodeEffectConfig(duration: 0.8, charset: Set(CharsetName.allCases))
}

extension DecodeEffectConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decodeIfPresent(FlexibleDouble.self, forKey: .duration) ?? Self.defaults.duration
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
