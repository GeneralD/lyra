public struct TextAppearance: Sendable {
    public let spacing: Double
    public let fontName: String
    public let fontSize: Double
    public let fontWeight: String
    public let color: ColorStyle
    public let shadow: ColorStyle
    public let lineHeight: Double

    public init(
        spacing: Double = 6,
        fontName: String = ".AppleSystemUIFont",
        fontSize: Double = 12,
        fontWeight: String = "regular",
        color: ColorStyle = .solid("#FFFFFFD9"),
        shadow: ColorStyle = .solid("#000000E6"),
        lineHeight: Double = 24
    ) {
        self.spacing = spacing
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.color = color
        self.shadow = shadow
        self.lineHeight = lineHeight
    }
}
