import MetadataDataSource
import ConfigDataSource
import Dependencies
import Domain
import LyricsDataSource

extension HealthCheckersKey: DependencyKey {
    public static let liveValue: [any HealthCheckable] = {
        let config = ConfigLoader.shared.load()

        var checkers: [any HealthCheckable] = [
            ConfigLoader.shared,
            LRCLibAPI.search(query: "test"),
            MusicBrainzAPI.searchRecording(title: "test", artist: nil, duration: nil),
        ]

        if let ai = config.ai {
            checkers.append(OpenAICompatibleAPI(config: AIEndpoint(
                endpoint: ai.endpoint, model: ai.model, apiKey: ai.apiKey
            )))
        } else {
            checkers.append(SkippedHealthCheck(serviceName: "AI endpoint", reason: "not configured"))
        }

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
