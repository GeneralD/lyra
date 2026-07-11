import Domain
import Foundation
import Testing

@testable import LyricsDataSource

@Suite("UtaNetHealthCheck")
struct UtaNetHealthCheckTests {
    @Test("serviceName is uta-net")
    func serviceName() {
        #expect(UtaNetHealthCheck().serviceName == "uta-net")
    }

    @Test("healthCheck passes for 2xx responses")
    func healthCheckPasses() async {
        let check = UtaNetHealthCheck {}

        let result = await check.healthCheck()

        #expect(result.status == .pass)
        #expect(result.detail.contains("reachable ("))
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports HTTP failures")
    func healthCheckHTTPFailure() async {
        let check = UtaNetHealthCheck {
            throw UtaNetError.httpStatus(503)
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 503")
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports request errors")
    func healthCheckError() async {
        let check = UtaNetHealthCheck {
            throw StubError("stubbed request failure")
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "stubbed request failure")
        #expect(result.latency == nil)
    }
}
