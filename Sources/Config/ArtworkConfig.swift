import Foundation

public struct ArtworkConfig: Sendable {
    public let size: CGFloat
    public let opacity: Double

    public init(size: CGFloat = 96, opacity: Double = 1.0) {
        self.size = size
        self.opacity = opacity
    }
}

extension ArtworkConfig: Codable {
    enum CodingKeys: String, CodingKey { case size, opacity }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.flexibleDoubleRequired(forKey: .size)
        opacity = try c.flexibleDouble(forKey: .opacity) ?? 1.0
    }
}
