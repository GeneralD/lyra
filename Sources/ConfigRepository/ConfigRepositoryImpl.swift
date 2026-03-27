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
            wallpaper: config.wallpaper.map { WallpaperStyle(location: $0.location, start: $0.start, end: $0.end) },
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
