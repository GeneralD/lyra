import Dependencies
import Domain
import Foundation
import Testing

@testable import MetadataDataSource

@Suite("LLMMetadataDataSourceImpl")
struct LLMMetadataDataSourceImplTests {
    @Test("Returns empty when AI is not configured")
    func unconfiguredReturnsEmpty() async {
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: nil)
        } operation: {
            LLMMetadataDataSourceImpl()
        }

        let result = await dataSource.resolve(track: Track(title: "Some Song", artist: "Some Artist"))
        #expect(result.isEmpty)
    }

    @Test("Default init() wires the production OpenAICompatibleAPI factory")
    func defaultFactoryWiresProductionAPI() async throws {
        // Cover the default `apiFactory` closure body which builds
        // `OpenAICompatibleAPI(provider: OpenAICompatibleAPI.provider(for:))`.
        // We route URLSession.shared through URLProtocolMock so the production
        // factory's resulting API hits a stubbed endpoint instead of the network.
        URLProtocolMock.register(host: "llm.invalid") { _ in
            let body = #"{"choices":[{"message":{"content":"{\"title\":\"Brave Shine\",\"artist\":\"Aimer\"}"}}]}"#
            return (
                HTTPURLResponse(url: URL(string: "http://llm.invalid/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }
        URLProtocol.registerClass(URLProtocolMock.self)
        defer { URLProtocolMock.unregister(host: "llm.invalid") }

        let config = try makeLLMConfig(endpoint: "http://llm.invalid")
        let result = await withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            await LLMMetadataDataSourceImpl().resolve(track: Track(title: "x", artist: "y"))
        }

        #expect(result == [Track(title: "Brave Shine", artist: "Aimer")])
    }
}

private enum LLMConfigFixtureError: Error { case invalidUTF8 }

private func makeLLMConfig(endpoint: String) throws -> ConfigLoadResult {
    let json = """
        { "ai": { "endpoint": "\(endpoint)", "model": "gpt-test", "api_key": "secret" } }
        """
    guard let data = json.data(using: .utf8) else { throw LLMConfigFixtureError.invalidUTF8 }
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
