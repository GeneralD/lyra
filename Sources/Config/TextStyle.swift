import Domain

public struct TextStyleConfig {
    public let font: String?
    public let size: Double?
    public let weight: String?
    public let color: ColorStyle?
    public let shadow: String?
    public let spacing: Double?

    public init(
        font: String? = nil,
        size: Double? = nil,
        weight: String? = nil,
        color: ColorStyle? = nil,
        shadow: String? = nil,
        spacing: Double? = nil
    ) {
        self.font = font
        self.size = size
        self.weight = weight
        self.color = color
        self.shadow = shadow
        self.spacing = spacing
    }
}

extension TextStyleConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case font, size, weight, color, shadow, spacing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        font = try c.decodeIfPresent(String.self, forKey: .font)
        size = try c.flexibleDouble(forKey: .size)
        weight = try c.decodeIfPresent(String.self, forKey: .weight)
        color = try c.decodeIfPresent(ColorStyle.self, forKey: .color)
        shadow = try c.decodeIfPresent(String.self, forKey: .shadow)
        spacing = try c.flexibleDouble(forKey: .spacing)
    }
}

extension TextStyleConfig {
    public func filled(with fallback: TextStyleConfig) -> TextStyleConfig {
        .init(
            font: font ?? fallback.font,
            size: size ?? fallback.size,
            weight: weight ?? fallback.weight,
            color: color ?? fallback.color,
            shadow: shadow ?? fallback.shadow,
            spacing: spacing ?? fallback.spacing
        )
    }
}
extension TextStyleConfig: Sendable {}
