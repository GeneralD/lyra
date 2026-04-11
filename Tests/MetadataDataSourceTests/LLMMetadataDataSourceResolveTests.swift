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
            LLMMetadataDataSourceImpl { request in
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let body = """
                    {"choices":[{"message":{"content":"{\\"title\\":\\"Brave Shine\\",\\"artist\\":\\"Aimer\\"}"}}]}
                    """.data(using: .utf8)!
                return (body, response)
            }
        }

        let result = await dataSource.resolve(track: Track(title: "brave shine", artist: "uploader"))

        #expect(result == [Track(title: "Brave Shine", artist: "Aimer")])
    }

    @Test("resolve returns empty when API status is not successful")
    func resolveHTTPFailure() async throws {
        let config = try makeConfig()
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            LLMMetadataDataSourceImpl { request in
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
        }

        let result = await dataSource.resolve(track: Track(title: "Song", artist: "Artist"))

        #expect(result.isEmpty)
    }

    @Test("resolve returns empty when response content cannot be decoded")
    func resolveInvalidContent() async throws {
        let config = try makeConfig()
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            LLMMetadataDataSourceImpl { request in
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let body = """
                    {"choices":[{"message":{"content":"not json"}}]}
                    """.data(using: .utf8)!
                return (body, response)
            }
        }

        let result = await dataSource.resolve(track: Track(title: "Song", artist: "Artist"))

        #expect(result.isEmpty)
    }

    @Test("resolve returns empty when request performer throws")
    func resolveRequestError() async throws {
        let config = try makeConfig()
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: config)
        } operation: {
            LLMMetadataDataSourceImpl { _ in
                throw LLMStubError()
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
            LLMMetadataDataSourceImpl { request in
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let body = """
                    {"choices":[{"message":{"content":"{\\"title\\":\\"\\",\\"artist\\":\\"Aimer\\"}"}}]}
                    """.data(using: .utf8)!
                return (body, response)
            }
        }

        let result = await dataSource.resolve(track: Track(title: "Song", artist: "Artist"))

        #expect(result.isEmpty)
    }
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
    return ConfigLoadResult(
        config: config,
        configDir: "/tmp",
        path: "/tmp/lyra.toml"
    )
}

private struct StubConfigDataSource: ConfigDataSource {
    var loadResult: ConfigLoadResult?
    func load() -> ConfigLoadResult? { loadResult }
    func tryDecode() throws -> String { "" }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

private struct LLMStubError: Error, LocalizedError, Sendable {
    var errorDescription: String? { "stubbed request failure" }
}
