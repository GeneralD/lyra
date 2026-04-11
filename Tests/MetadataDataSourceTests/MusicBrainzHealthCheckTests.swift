import Domain
import Foundation
import Testing

@testable import MetadataDataSource

@Suite("MusicBrainzHealthCheck")
struct MusicBrainzHealthCheckTests {
    private let api = MusicBrainzAPI.searchRecording(title: "Song", artist: "Artist", duration: nil)

    @Test("healthCheck passes for 2xx responses")
    func healthCheckPasses() async {
        let result = await api.healthCheck { request in
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("lyra") == true)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        #expect(result.status == .pass)
        #expect(result.detail.contains("reachable ("))
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports HTTP failures")
    func healthCheckHTTPFailure() async {
        let result = await api.healthCheck { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 503")
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports request errors")
    func healthCheckError() async {
        let result = await api.healthCheck { _ in
            throw MusicBrainzStubError()
        }

        #expect(result.status == HealthCheckResult.Status.fail)
        #expect(result.detail == "stubbed request failure")
        #expect(result.latency == nil)
    }
}

private struct MusicBrainzStubError: Error, LocalizedError, Sendable {
    var errorDescription: String? { "stubbed request failure" }
}
