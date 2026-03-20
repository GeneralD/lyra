import AppKit
import Config
import Dependencies
import Domain

extension TextAppearanceConfig {
    @MainActor
    func toTextAppearance() -> TextAppearance {
        let available = NSFontManager.shared.availableFontFamilies.contains(fontName)
        let nsFont = available ? NSFont(name: fontName, size: fontSize) : nil
        let fallback = NSFont.systemFont(ofSize: fontSize)
        let lineHeight = ceil(
            (nsFont?.ascender ?? fallback.ascender)
                - (nsFont?.descender ?? fallback.descender)
                + (nsFont?.leading ?? fallback.leading)
        ) + spacing * 2

        return TextAppearance(
            spacing: spacing,
            fontName: fontName,
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            shadow: shadow,
            lineHeight: lineHeight
        )
    }
}

extension AppConfig {
    @MainActor
    public func toAppStyle() -> AppStyle {
        AppStyle(
            text: TextLayout(
                title: text.title.toTextAppearance(),
                artist: text.artist.toTextAppearance(),
                lyric: text.lyric.toTextAppearance(),
                highlight: text.highlight.toTextAppearance(),
                decodeEffect: DecodeEffect(
                    duration: text.decodeEffect.duration.value,
                    charsets: text.decodeEffect.charset
                )
            ),
            artwork: ArtworkStyle(size: artwork.size.value, opacity: artwork.opacity.value),
            ripple: RippleStyle(
                enabled: ripple.enabled,
                color: .solid(ripple.color),
                radius: ripple.radius.value,
                duration: ripple.duration.value,
                idle: ripple.idle.value
            ),
            screen: screen,
            wallpaperURL: wallpaper.map { URL(fileURLWithPath: $0) },
            ai: ai.map { AIEndpoint(endpoint: $0.endpoint, model: $0.model, apiKey: $0.apiKey) }
        )
    }
}

// MARK: - DependencyKey registration

extension AppStyleKey: DependencyKey {
    public static let liveValue: AppStyle = MainActor.assumeIsolated {
        ConfigLoader.shared.load().toAppStyle()
    }
}
