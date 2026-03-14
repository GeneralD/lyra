public struct TextStyleConfig: Codable, Sendable {
    public let font: String?
    public let size: Double?
    public let weight: String?
    public let color: String?
    public let shadow: String?
    public let spacing: Double?

    public init(
        font: String? = nil,
        size: Double? = nil,
        weight: String? = nil,
        color: String? = nil,
        shadow: String? = nil,
        spacing: Double? = nil
    ) {
        self.font = font; self.size = size; self.weight = weight
        self.color = color; self.shadow = shadow; self.spacing = spacing
    }

    public func merging(over base: TextStyleConfig) -> TextStyleConfig {
        .init(
            font: font ?? base.font,
            size: size ?? base.size,
            weight: weight ?? base.weight,
            color: color ?? base.color,
            shadow: shadow ?? base.shadow,
            spacing: spacing ?? base.spacing
        )
    }
}
