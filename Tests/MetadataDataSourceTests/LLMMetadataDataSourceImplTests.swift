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

    @Test("Default init() wires the production OpenAICompatibleAPI factory (degrades to empty on refused port)")
    func defaultFactoryWiresProductionAPI() async throws {
        // Cover the default `apiFactory` closure body which builds
        // `OpenAICompatibleAPI(provider: OpenAICompatibleAPI.provider(for:))`.
        // The provider owns a private ephemeral URLSession (#318), so a globally
        // registered URLProtocol mock cannot intercept it; point the endpoint at
        // a refused local port instead — same pattern as
        // OpenAICompatibleHealthCheckDefaultBackendTests — and assert the
        // graceful empty fallback. The success path through the API is covered
        // by the apiFactory-injected resolve tests.
        let config = try makeLLMConfig(endpoint: "http://127.0.0.1:1")
        let result = await withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            await LLMMetadataDataSourceImpl().resolve(track: Track(title: "x", artist: "y"))
        }

        #expect(result.isEmpty)
    }
}

private enum LLMConfigFixtureError: Error { case invalidUTF8 }

private func makeLLMConfig(endpoint: String) throws -> ConfigLoadResult {
    let json = """
        { "ai": { "endpoint": "\(endpoint)", "model": "gpt-test", "api_key": "secret" } }
        """
    guard let data = json.data(using: .utf8) else { throw LLMConfigFixtureError.invalidUTF8 }
    let config = try JSONDecoder().decode(AppConfig.self, from: data)
    return ConfigLoadResult(config: config, configDir: "/tmp")
}

private struct StubConfigDataSource: ConfigDataSource {
    var loadResult: ConfigLoadResult?
    func load() -> ConfigLoadResult? { loadResult }
    func tryDecode() throws -> String { "" }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
    var configDir: String { "" }
}
