import Domain

public struct DecodeEffectConfig: Sendable {
    public let duration: Double
    public let charset: Set<CharsetName>
}

extension DecodeEffectConfig {
    static let defaults = DecodeEffectConfig(duration: 0.8, charset: Set(CharsetName.allCases))
}

extension DecodeEffectConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.flexibleDouble(forKey: .duration) ?? Self.defaults.duration
        switch (try? container.decodeIfPresent([CharsetName].self, forKey: .charset), try? container.decodeIfPresent(CharsetName.self, forKey: .charset)) {
        case let (.some(arr), _):
            charset = Set(arr)
        case let (_, .some(single)):
            charset = [single]
        default:
            charset = Self.defaults.charset
        }
    }
}
