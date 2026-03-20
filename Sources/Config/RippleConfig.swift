import Foundation

public struct RippleConfig: Sendable {
    public let enabled: Bool
    public let color: String
    public let radius: Double
    public let duration: Double
    public let idle: Double

    public init(enabled: Bool = true, color: String = "#AAAAFFFF", radius: Double = 60, duration: Double = 0.6, idle: Double = 1) {
        self.enabled = enabled
        self.color = color
        self.radius = radius
        self.duration = duration
        self.idle = idle
    }
}

extension RippleConfig: Codable {
    enum CodingKeys: String, CodingKey { case enabled, color, radius, duration, idle }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        color = try c.decode(String.self, forKey: .color)
        radius = try c.flexibleDoubleRequired(forKey: .radius)
        duration = try c.flexibleDoubleRequired(forKey: .duration)
        idle = try c.flexibleDoubleRequired(forKey: .idle)
    }
}
