import AppKit
import Dependencies
import Domain

// MARK: - FontMetricsProvider (AppKit implementation)

struct AppKitFontMetrics: FontMetricsProvider {
    @MainActor func lineHeight(fontName: String, fontSize: Double, spacing: Double) -> Double {
        let available = NSFontManager.shared.availableFontFamilies.contains(fontName)
        let nsFont = available ? NSFont(name: fontName, size: fontSize) : nil
        let fallback = NSFont.systemFont(ofSize: fontSize)
        return ceil(
            (nsFont?.ascender ?? fallback.ascender)
                - (nsFont?.descender ?? fallback.descender)
                + (nsFont?.leading ?? fallback.leading)
        ) + spacing * 2
    }
}

extension FontMetricsProviderKey: DependencyKey {
    public static let liveValue: any FontMetricsProvider = AppKitFontMetrics()
}

// MARK: - AppStyle DI registration

extension AppStyleKey: DependencyKey {
    public static let liveValue: AppStyle = MainActor.assumeIsolated {
        @Dependency(\.configUseCase) var configUseCase
        return configUseCase.loadAppStyle()
    }
}
