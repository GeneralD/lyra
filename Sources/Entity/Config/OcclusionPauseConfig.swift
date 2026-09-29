public struct OcclusionPauseConfig {
    public let enabled: Bool
    public let threshold: FlexibleDouble
}

extension OcclusionPauseConfig: Sendable {}

extension OcclusionPauseConfig {
    static let defaults = OcclusionPauseConfig(enabled: false, threshold: 0.9)
}

extension OcclusionPauseConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.defaults.enabled
        threshold = try container.decodeIfPresent(FlexibleDouble.self, forKey: .threshold) ?? Self.defaults.threshold
    }
}
