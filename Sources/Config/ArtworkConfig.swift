import Foundation

public struct ArtworkConfig: Sendable {
    public let size: CGFloat
    public let opacity: Double
}

extension ArtworkConfig {
    static let defaults = ArtworkConfig(size: 96, opacity: 1.0)
}

extension ArtworkConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.flexibleDouble(forKey: .size) ?? Self.defaults.size
        opacity = try container.flexibleDouble(forKey: .opacity) ?? Self.defaults.opacity
    }
}
