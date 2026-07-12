import Foundation
import Testing

@testable import ScopedAPISession

@Suite("ScopedAPISession")
struct ScopedAPISessionTests {
    @Test("withAPI hands the built client to the body and returns its result")
    func withAPIForwardsResult() async {
        let scoped = ScopedAPISession(timeout: 10) { _ in "client" }

        let result = await scoped.withAPI { "\($0)-ok" }

        #expect(result == "client-ok")
    }

    @Test("makeAPI receives a live session configured with the given timeout")
    func makeAPIReceivesConfiguredSession() async {
        let scoped = ScopedAPISession(timeout: 42) { $0.configuration.timeoutIntervalForRequest }

        let timeout = await scoped.withAPI { $0 }

        #expect(timeout == 42)
    }

    @Test("withAPI rethrows an error thrown by the body")
    func withAPIRethrows() async {
        struct Boom: Error {}
        let scoped = ScopedAPISession(timeout: 10) { _ in 0 }

        await #expect(throws: Boom.self) {
            _ = try await scoped.withAPI { _ in throw Boom() }
        }
    }

    @Test("each withAPI call builds a fresh session instance")
    func eachCallBuildsFreshSession() async {
        let scoped = ScopedAPISession(timeout: 10) { ObjectIdentifier($0) }

        let first = await scoped.withAPI { $0 }
        let second = await scoped.withAPI { $0 }

        #expect(first != second)
    }
}
