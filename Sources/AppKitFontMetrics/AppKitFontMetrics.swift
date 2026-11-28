import AppKit
import Domain

public struct AppKitFontMetrics {
    public init() {}
}

extension AppKitFontMetrics: FontMetricsProvider {
    @MainActor public func lineHeight(fontName: String, fontSize: Double, spacing: Double) -> Double {
        let font = resolveFont(name: fontName, size: fontSize)
        return ceil(font.ascender - font.descender + font.leading) + spacing * 2
    }
}

extension AppKitFontMetrics {
    @MainActor private func resolveFont(name: String, size: Double) -> NSFont {
        NSFont(name: name, size: size)
            ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
            ?? .systemFont(ofSize: size)
    }
}
