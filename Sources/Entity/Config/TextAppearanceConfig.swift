public struct TextAppearanceConfig {
    public let fontName: String
    public let fontSize: Double
    public let fontWeight: String
    public let color: ColorStyle
    public let shadow: ColorStyle
    public let spacing: Double
}

extension TextAppearanceConfig: Sendable {}
extension TextAppearanceConfig: Codable {}

extension TextAppearanceConfig {
    static let defaults = TextAppearanceConfig(
        fontName: "Helvetica Neue", fontSize: 12, fontWeight: "regular",
        color: .solid("#FFFFFFD9"), shadow: .solid("#000000E6"), spacing: 6
    )
}
