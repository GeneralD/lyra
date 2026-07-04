import Dependencies
import Domain
import Foundation

public struct ConfigRepositoryImpl {
    @Dependency(\.configDataSource) private var dataSource

    public init() {}
}

extension ConfigRepositoryImpl: ConfigRepository {
    public func loadAppStyle() -> AppStyle {
        guard let result = dataSource.load() else { return .init() }

        let config = result.config

        return AppStyle(
            text: TextLayout(
                title: config.text.title.toTextAppearance(),
                artist: config.text.artist.toTextAppearance(),
                lyric: config.text.lyric.toTextAppearance(),
                highlight: config.text.highlight.toTextAppearance(),
                decodeEffect: DecodeEffect(
                    duration: config.text.decodeEffect.duration.value,
                    charsets: config.text.decodeEffect.charset,
                    processingColor: config.text.decodeEffect.processingColor
                )
            ),
            artwork: ArtworkStyle(size: config.artwork.size.value, opacity: config.artwork.opacity.value),
            ripple: RippleStyle(
                enabled: config.ripple.enabled,
                color: .solid(config.ripple.color),
                radius: config.ripple.radius.value,
                duration: config.ripple.duration.value,
                idle: config.ripple.idle.value,
                shape: config.ripple.shape
            ),
            spectrum: SpectrumStyle(
                enabled: config.spectrum.enabled,
                stereo: config.spectrum.stereo,
                barColor: config.spectrum.barColor,
                gradientDirection: config.spectrum.gradientDirection,
                backgroundColor: config.spectrum.backgroundColor,
                // Floored to a visible thickness / non-negative gap; the bar
                // count is derived from the overlay width at render time.
                barWidth: max(1, config.spectrum.barWidth.value),
                barSpacing: max(0, config.spectrum.barSpacing.value),
                // Ordered and floored so the analyzer always gets a valid
                // ascending band range.
                minFreq: max(1, min(config.spectrum.minFreq.value, config.spectrum.maxFreq.value)),
                maxFreq: max(config.spectrum.minFreq.value + 1, config.spectrum.maxFreq.value),
                minDb: config.spectrum.minDb.value,
                maxDb: config.spectrum.maxDb.value,
                scale: config.spectrum.scale,
                // Config uses cava's familiar 0–100 scale; the style stores
                // the 0…1 fraction, capped below 1 so the integral converges.
                noiseReduction: min(max(config.spectrum.noiseReduction.value / 100, 0), 0.97),
                fftSize: max(64, Int(config.spectrum.fftSize.value)),
                placement: config.spectrum.placement,
                heightRatio: config.spectrum.heightRatio.value,
                // Optional absolute clamp on the growth extent; floored at 0,
                // otherwise passed straight through (nil = unclamped).
                minHeight: config.spectrum.minHeight.map { max(0, $0.value) },
                maxHeight: config.spectrum.maxHeight.map { max(0, $0.value) }
            ),
            screen: config.screen,
            screenDebounce: config.screenDebounce.value,
            wallpaper: config.wallpaper.map { cfg in
                WallpaperStyle(
                    items: cfg.items.map {
                        WallpaperItem(
                            location: $0.location,
                            start: $0.start,
                            end: $0.end,
                            scale: $0.scale)
                    },
                    mode: cfg.mode
                )
            },
            configDir: result.configDir,
            ai: config.ai.map { AIEndpoint(endpoint: $0.endpoint, model: $0.model, apiKey: $0.apiKey) }
        )
    }

    public func template(format: ConfigFormat) -> String? {
        dataSource.template(format: format)
    }

    public func writeTemplate(format: ConfigFormat, force: Bool) throws -> String {
        try dataSource.writeTemplate(format: format, force: force)
    }

    public var existingConfigPath: String? {
        dataSource.existingConfigPath
    }

    public func validate() -> ConfigValidationResult {
        do {
            let path = try dataSource.tryDecode()
            guard !path.isEmpty else { return .defaults }
            return .loaded(path: path)
        } catch {
            return .decodeError(path: "config", error: error.localizedDescription)
        }
    }
}

extension ConfigRepositoryImpl: HealthCheckable {
    public var serviceName: String { "Config" }

    public func healthCheck() async -> HealthCheckResult {
        switch validate() {
        case .loaded(let path):
            return HealthCheckResult(status: .pass, detail: "loaded (\(path))")
        case .defaults:
            return HealthCheckResult(status: .pass, detail: "using defaults (no config file found)")
        case .unreadable(let path):
            return HealthCheckResult(status: .fail, detail: "cannot read \(path)")
        case .decodeError(let path, let error):
            return HealthCheckResult(status: .fail, detail: "decode error in \(path): \(error)")
        }
    }
}

extension TextAppearanceConfig {
    func toTextAppearance() -> TextAppearance {
        TextAppearance(
            spacing: spacing,
            fontName: fontName,
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            shadow: shadow
        )
    }
}
