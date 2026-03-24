import Dependencies
import Domain
import Foundation

public struct ConfigRepositoryImpl {
    @Dependency(\.fontMetrics) private var fontMetrics
    @Dependency(\.configDataSource) private var dataSource

    public init() {}
}

extension ConfigRepositoryImpl: ConfigRepository {
    @MainActor
    public func loadAppStyle() -> AppStyle {
        guard let result = dataSource.load() else { return .init() }

        let config = result.config
        let wallpaper = config.wallpaper.map { resolveWallpaperPath($0, configDir: result.configDir) }

        return AppStyle(
            text: TextLayout(
                title: config.text.title.toTextAppearance(fontMetrics: fontMetrics),
                artist: config.text.artist.toTextAppearance(fontMetrics: fontMetrics),
                lyric: config.text.lyric.toTextAppearance(fontMetrics: fontMetrics),
                highlight: config.text.highlight.toTextAppearance(fontMetrics: fontMetrics),
                decodeEffect: DecodeEffect(
                    duration: config.text.decodeEffect.duration.value,
                    charsets: config.text.decodeEffect.charset
                )
            ),
            artwork: ArtworkStyle(size: config.artwork.size.value, opacity: config.artwork.opacity.value),
            ripple: RippleStyle(
                enabled: config.ripple.enabled,
                color: .solid(config.ripple.color),
                radius: config.ripple.radius.value,
                duration: config.ripple.duration.value,
                idle: config.ripple.idle.value
            ),
            screen: config.screen,
            wallpaperURL: wallpaper.map { URL(fileURLWithPath: $0) },
            ai: config.ai.map { AIEndpoint(endpoint: $0.endpoint, model: $0.model, apiKey: $0.apiKey) }
        )
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

// MARK: - Private

extension ConfigRepositoryImpl {
    fileprivate func resolveWallpaperPath(_ wallpaper: String, configDir: String) -> String {
        guard !wallpaper.hasPrefix("/") else { return wallpaper }
        return URL(fileURLWithPath: configDir).appendingPathComponent(wallpaper).path
    }
}

extension TextAppearanceConfig {
    func toTextAppearance(fontMetrics: any FontMetricsProvider) -> TextAppearance {
        let lh = MainActor.assumeIsolated {
            fontMetrics.lineHeight(fontName: fontName, fontSize: fontSize, spacing: spacing)
        }
        return TextAppearance(
            spacing: spacing,
            fontName: fontName,
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            shadow: shadow,
            lineHeight: lh
        )
    }
}
