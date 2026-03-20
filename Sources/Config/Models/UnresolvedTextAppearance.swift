import Domain

struct UnresolvedTextAppearance: Codable {
    var fontName: String?
    var fontSize: FlexibleDouble?
    var fontWeight: String?
    var color: ColorStyle?
    var shadow: ColorStyle?
    var spacing: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case fontName = "font"
        case fontSize = "size"
        case fontWeight = "weight"
        case color, shadow, spacing
    }
}

extension UnresolvedTextAppearance {
    static let defaults = UnresolvedTextAppearance(
        fontName: "Helvetica Neue", fontSize: 12.0, fontWeight: "regular",
        color: .solid("#FFFFFFD9"), shadow: .solid("#000000E6"), spacing: 6.0
    )

    static let titleDefaults = UnresolvedTextAppearance(fontSize: 18.0, fontWeight: "bold")
    static let artistDefaults = UnresolvedTextAppearance(fontWeight: "medium")
    static let highlightDefaults = UnresolvedTextAppearance(
        color: .gradient(["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"])
    )

    func resolve(defaults: UnresolvedTextAppearance..., filled: TextAppearanceConfig) -> TextAppearanceConfig {
        resolve(defaults: defaults, filled: filled)
    }
}

fileprivate extension UnresolvedTextAppearance {
    func resolve(defaults: [UnresolvedTextAppearance], filled: TextAppearanceConfig) -> TextAppearanceConfig {
        guard let first = defaults.first else {
            return TextAppearanceConfig(
                fontName: fontName ?? filled.fontName,
                fontSize: fontSize?.value ?? filled.fontSize,
                fontWeight: fontWeight ?? filled.fontWeight,
                color: color ?? filled.color,
                shadow: shadow ?? filled.shadow,
                spacing: spacing?.value ?? filled.spacing
            )
        }
        let merged = UnresolvedTextAppearance(
            fontName: fontName ?? first.fontName,
            fontSize: fontSize ?? first.fontSize,
            fontWeight: fontWeight ?? first.fontWeight,
            color: color ?? first.color,
            shadow: shadow ?? first.shadow,
            spacing: spacing ?? first.spacing
        )
        return merged.resolve(defaults: Array(defaults.dropFirst()), filled: filled)
    }
}


extension Optional where Wrapped == UnresolvedTextAppearance {
    func resolve(defaults: UnresolvedTextAppearance..., filled: TextAppearanceConfig) -> TextAppearanceConfig {
        (self ?? .init()).resolve(defaults: defaults, filled: filled)
    }
}