import Dependencies
import Domain
import Foundation
import Testing

@testable import MetadataDataSource

@Suite("LLMMetadataDataSourceImpl resolve")
struct LLMMetadataDataSourceResolveTests {
    @Test("resolve returns normalized track from API response")
    func resolveSuccess() async throws {
        let config = try makeConfig()
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            LLMMetadataDataSourceImpl { _ in
                OpenAICompatibleStub { _ in
                    .init(choices: [.init(message: .init(content: #"{"title":"Brave Shine","artist":"Aimer"}"#))])
                }
            }
        }

        let result = await dataSource.resolve(track: Track(title: "brave shine", artist: "uploader"))

        #expect(result == [Track(title: "Brave Shine", artist: "Aimer")])
    }

    @Test("resolve returns empty when API throws")
    func resolveAPIError() async throws {
        let config = try makeConfig()
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            LLMMetadataDataSourceImpl { _ in
                OpenAICompatibleStub { _ in throw StubError() }
            }
        }

        let result = await dataSource.resolve(track: Track(title: "Song", artist: "Artist"))

        #expect(result.isEmpty)
    }

    @Test("resolve returns empty when message content cannot be decoded")
    func resolveInvalidContent() async throws {
        let config = try makeConfig()
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            LLMMetadataDataSourceImpl { _ in
                OpenAICompatibleStub { _ in
                    .init(choices: [.init(message: .init(content: "not json"))])
                }
            }
        }

        let result = await dataSource.resolve(track: Track(title: "Song", artist: "Artist"))

        #expect(result.isEmpty)
    }

    @Test("resolve returns empty when extracted title is empty")
    func resolveEmptyTitle() async throws {
        let config = try makeConfig()
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            LLMMetadataDataSourceImpl { _ in
                OpenAICompatibleStub { _ in
                    .init(choices: [.init(message: .init(content: #"{"title":"","artist":"Aimer"}"#))])
                }
            }
        }

        let result = await dataSource.resolve(track: Track(title: "Song", artist: "Artist"))

        #expect(result.isEmpty)
    }

    @Test("resolve returns empty when there are no choices")
    func resolveNoChoices() async throws {
        let config = try makeConfig()
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            LLMMetadataDataSourceImpl { _ in
                OpenAICompatibleStub { _ in .init(choices: []) }
            }
        }

        let result = await dataSource.resolve(track: Track(title: "Song", artist: "Artist"))

        #expect(result.isEmpty)
    }

    @Test("resolve forwards configured model and raw track text to the prompt")
    func resolvePassesModelAndPrompt() async throws {
        let config = try makeConfig()
        let captured = RequestRecorder()
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            LLMMetadataDataSourceImpl { _ in
                OpenAICompatibleStub { request in
                    await captured.set(request)
                    return .init(choices: [.init(message: .init(content: #"{"title":"X","artist":"Y"}"#))])
                }
            }
        }

        _ = await dataSource.resolve(track: Track(title: "Some Title", artist: "Some Uploader"))
        let request = await captured.value

        #expect(request?.model == "gpt-test")
        #expect(request?.messages.first(where: { $0.role == "user" })?.content.contains("\"title\": \"Some Title\"") == true)
        #expect(request?.messages.first(where: { $0.role == "user" })?.content.contains("\"artist\": \"Some Uploader\"") == true)
        #expect(request?.responseFormat.type == "json_object")
        #expect(request?.temperature == 0)
    }
}

private actor RequestRecorder {
    private(set) var value: ChatCompletionRequest?
    func set(_ value: ChatCompletionRequest) { self.value = value }
}

private enum LLMFixtureError: Error {
    case invalidUTF8
}

private func makeConfig() throws -> ConfigLoadResult {
    guard
        let data = """
            {
              "ai": {
                "endpoint": "https://api.example.com",
                "model": "gpt-test",
                "api_key": "secret-key"
              }
            }
            """.data(using: .utf8)
    else {
        throw LLMFixtureError.invalidUTF8
    }
    let config = try JSONDecoder().decode(AppConfig.self, from: data)
    return ConfigLoadResult(config: config, configDir: "/tmp", path: "/tmp/lyra.toml")
}

private struct StubConfigDataSource: ConfigDataSource {
    var loadResult: ConfigLoadResult?
    func load() -> ConfigLoadResult? { loadResult }
    func tryDecode() throws -> String { "" }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}
