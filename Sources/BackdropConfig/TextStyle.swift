public struct TextStyleConfig: Sendable {
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
        color = try c.decodeIfPresent(String.self, forKey: .color)
        shadow = try c.decodeIfPresent(String.self, forKey: .shadow)
        spacing = try c.flexibleDouble(forKey: .spacing)
    }
}

extension TextStyleConfig {
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

/// highlight section: TextStyleConfig + gradient colors
public struct HighlightConfig: Sendable {
    public let color: [String]
    public let style: TextStyleConfig

    public init(
        color: [String] = ["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"],
        style: TextStyleConfig = .init()
    ) {
        self.color = color
        self.style = style
    }
}

extension HighlightConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case color, font, size, weight, shadow, spacing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent([String].self, forKey: .color)
            ?? ["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"]
        style = TextStyleConfig(
            font: try c.decodeIfPresent(String.self, forKey: .font),
            size: try c.flexibleDouble(forKey: .size),
            weight: try c.decodeIfPresent(String.self, forKey: .weight),
            shadow: try c.decodeIfPresent(String.self, forKey: .shadow),
            spacing: try c.flexibleDouble(forKey: .spacing)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(style.font, forKey: .font)
        try c.encodeIfPresent(style.size, forKey: .size)
        try c.encodeIfPresent(style.weight, forKey: .weight)
        try c.encodeIfPresent(style.shadow, forKey: .shadow)
        try c.encodeIfPresent(style.spacing, forKey: .spacing)
    }
}
