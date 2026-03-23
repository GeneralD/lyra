import AIService
import Config
import Dependencies
import Domain
import LRCLibService
import MusicBrainzService

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
        }

        return checkers
    }()
}
