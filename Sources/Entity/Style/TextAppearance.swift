public struct TextAppearance {
    public let spacing: Double
    public let fontName: String
    public let fontSize: Double
    public let fontWeight: String
    public let color: ColorStyle
    public let shadow: ColorStyle

    public init(
        spacing: Double = 6,
        fontName: String = ".AppleSystemUIFont",
        fontSize: Double = 12,
        fontWeight: String = "regular",
        color: ColorStyle = .solid("#FFFFFFD9"),
        shadow: ColorStyle = .solid("#000000E6")
    ) {
        self.spacing = spacing
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.color = color
        self.shadow = shadow
    }
}

extension TextAppearance: Sendable {}
