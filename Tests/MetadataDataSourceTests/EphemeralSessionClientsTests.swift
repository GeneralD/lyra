import Domain
import Foundation
@preconcurrency import Papyrus
import Testing

@testable import MetadataDataSource

@Suite("EphemeralSession API wrappers")
struct EphemeralSessionClientsTests {
    @Test("default inits build the live clients")
    func defaultInitsInstantiate() {
        // Construction only — no network call. Covers the live wiring.
        _ = EphemeralSessionMusicBrainz()
        _ = EphemeralSessionOpenAICompatible(
            config: AIEndpoint(endpoint: "http://127.0.0.1:1", model: "m", apiKey: "k")
        )
    }

    @Test("MusicBrainz wrapper forwards searchRecording and healthCheck")
    func musicBrainzForwards() async throws {
        let wrapper = EphemeralSessionMusicBrainz(
            api: MusicBrainzStub(),
            session: URLSession(configuration: .ephemeral)
        )

        let response = try await wrapper.searchRecording(query: "q", fmt: "json", limit: 5)
        let health = try await wrapper.healthCheck()

        #expect(response.recordings.isEmpty)
        #expect(health.statusCode == 200)
    }

    @Test("OpenAI wrapper forwards chatCompletion")
    func openAIForwards() async throws {
        let wrapper = EphemeralSessionOpenAICompatible(
            api: OpenAICompatibleStub { _ in .init(choices: [.init(message: .init(content: "ok"))]) },
            session: URLSession(configuration: .ephemeral)
        )

        let response = try await wrapper.chatCompletion(request: ChatCompletionRequest(model: "m", messages: []))

        #expect(response.choices.first?.message.content == "ok")
    }
}
