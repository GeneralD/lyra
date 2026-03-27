public struct RippleConfig {
    public let enabled: Bool
    public let color: ColorConfig
    public let radius: FlexibleDouble
    public let duration: FlexibleDouble
    public let idle: FlexibleDouble
}

extension RippleConfig: Sendable {}

extension RippleConfig {
    static let defaults = RippleConfig(enabled: true, color: "#AAAAFFFF", radius: 60, duration: 0.6, idle: 1)
}

extension RippleConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.defaults.enabled
        color = try container.decodeIfPresent(ColorConfig.self, forKey: .color) ?? Self.defaults.color
        radius = try container.decodeIfPresent(FlexibleDouble.self, forKey: .radius) ?? Self.defaults.radius
        duration = try container.decodeIfPresent(FlexibleDouble.self, forKey: .duration) ?? Self.defaults.duration
        idle = try container.decodeIfPresent(FlexibleDouble.self, forKey: .idle) ?? Self.defaults.idle
    }
}
