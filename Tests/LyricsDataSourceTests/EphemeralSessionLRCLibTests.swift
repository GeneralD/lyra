import Domain
import Foundation
@preconcurrency import Papyrus
import Testing

@testable import LyricsDataSource

@Suite("EphemeralSessionLRCLib")
struct EphemeralSessionLRCLibTests {
    @Test("default init builds the live client")
    func defaultInitInstantiates() {
        // Construction only — no network call. Covers the live wiring.
        _ = EphemeralSessionLRCLib()
    }

    @Test("forwards get / search / healthCheck to the wrapped API")
    func forwardsCalls() async throws {
        let wrapper = EphemeralSessionLRCLib(
            api: LRCLibStub(
                get: { trackName, artistName, _ in
                    LyricsResult(trackName: trackName, artistName: artistName, plainLyrics: "lyrics")
                },
                search: { q in [LyricsResult(trackName: q, artistName: "A", plainLyrics: "P")] }
            ),
            session: URLSession(configuration: .ephemeral)
        )

        let got = try await wrapper.get(trackName: "Numb", artistName: "Linkin Park", duration: 187)
        let found = try await wrapper.search(q: "numb")
        let health = try await wrapper.healthCheck()

        #expect(got.trackName == "Numb")
        #expect(got.artistName == "Linkin Park")
        #expect(found.first?.trackName == "numb")
        #expect(health.statusCode == 200)
    }
}
