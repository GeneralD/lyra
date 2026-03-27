public struct ArtworkConfig {
    public let size: FlexibleDouble
    public let opacity: FlexibleDouble
}

extension ArtworkConfig: Sendable {}

extension ArtworkConfig {
    static let defaults = ArtworkConfig(size: 96, opacity: 1.0)
}

extension ArtworkConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(FlexibleDouble.self, forKey: .size) ?? Self.defaults.size
        opacity = try container.decodeIfPresent(FlexibleDouble.self, forKey: .opacity) ?? Self.defaults.opacity
    }
}
