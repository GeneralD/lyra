import ConfigRepository
import Dependencies
import Domain
import LyricsDataSource
import MetadataDataSource
import WallpaperDataSource

extension HealthCheckersKey: DependencyKey {
    public static let liveValue: [any HealthCheckable] = {
        @Dependency(\.appStyle) var appStyle

        var checkers: [any HealthCheckable] = [
            ConfigRepositoryImpl(),
            LRCLibAPI.search(query: "test"),
            MusicBrainzAPI.searchRecording(title: "test", artist: nil, duration: nil),
        ]

        if let ai = appStyle.ai {
            checkers.append(OpenAICompatibleAPI(config: ai))
        } else {
            checkers.append(SkippedHealthCheck(serviceName: "AI endpoint", reason: "not configured"))
        }

        // YouTube wallpaper tool availability (always check regardless of config)
        checkers.append(contentsOf: WallpaperToolChecker.youtubeCheckers())

        return checkers
    }()
}

private struct SkippedHealthCheck: HealthCheckable {
    let serviceName: String
    let reason: String

    func healthCheck() async -> HealthCheckResult {
        HealthCheckResult(status: .skip, detail: reason)
    }
}
