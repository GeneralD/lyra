import ConfigRepository
import Dependencies
import Domain
import Foundation
import LyricsDataSource
import MetadataDataSource
@preconcurrency import Papyrus
import ScopedAPISession
import WallpaperDataSource

extension HealthCheckersKey: DependencyKey {
    public static let liveValue: [any HealthCheckable] = {
        @Dependency(\.configDataSource) var configDataSource

        var checkers: [any HealthCheckable] = [
            ConfigRepositoryImpl(),
            LRCLibHealthCheck {
                try await ScopedAPISession(timeout: 10) {
                    LRCLibAPI(provider: Provider(baseURL: LRCLibAPI.baseURL, urlSession: $0))
                }.withAPI { _ = try await $0.healthCheck() }
            },
            MusicBrainzHealthCheck {
                try await ScopedAPISession(timeout: 10) {
                    MusicBrainzAPI(provider: Provider(baseURL: MusicBrainzAPI.baseURL, urlSession: $0))
                }.withAPI { _ = try await $0.healthCheck() }
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
