import ConfigRepository
import Dependencies
import Domain
import Foundation
import LyricsDataSource
import MetadataDataSource
@preconcurrency import Papyrus
import WallpaperDataSource

extension HealthCheckersKey: DependencyKey {
    public static let liveValue: [any HealthCheckable] = {
        @Dependency(\.configDataSource) var configDataSource

        var checkers: [any HealthCheckable] = [
            ConfigRepositoryImpl(),
            LRCLibHealthCheck {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 10
                let session = URLSession(configuration: configuration)
                let api = LRCLibAPI(provider: Provider(baseURL: LRCLibAPI.baseURL, urlSession: session))
                _ = try await api.healthCheck()
            },
            MusicBrainzHealthCheck {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 10
                let session = URLSession(configuration: configuration)
                let api = MusicBrainzAPI(provider: Provider(baseURL: MusicBrainzAPI.baseURL, urlSession: session))
                _ = try await api.healthCheck()
            },
        ]

        if let ai = configDataSource.load()?.config.ai {
            checkers.append(
                OpenAICompatibleHealthCheck(
                    config: AIEndpoint(endpoint: ai.endpoint, model: ai.model, apiKey: ai.apiKey)
                )
            )
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
