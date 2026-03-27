import AppKit
import Dependencies
import Domain

struct AppKitFontMetrics: FontMetricsProvider {
    @MainActor func lineHeight(fontName: String, fontSize: Double, spacing: Double) -> Double {
        let font = resolveFont(name: fontName, size: fontSize)
        return ceil(font.ascender - font.descender + font.leading) + spacing * 2
    }

    @MainActor private func resolveFont(name: String, size: Double) -> NSFont {
        NSFont(name: name, size: size)
            ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
            ?? .systemFont(ofSize: size)
    }
}

extension FontMetricsProviderKey: DependencyKey {
    public static let liveValue: any FontMetricsProvider = AppKitFontMetrics()
}
