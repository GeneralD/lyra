import Domain
import Testing

@testable import SQLiteDataStore

@Suite("GRDBLLMMetadataDataStore")
struct GRDBLLMMetadataDataStoreTests {
    private func makeStore() throws -> GRDBLLMMetadataDataStore {
        GRDBLLMMetadataDataStore(dbManager: try DatabaseManager(inMemory: true))
    }

    @Test("read returns nil for unknown key")
    func readReturnsNil() async throws {
        let store = try makeStore()
        let result = await store.read(title: "Unknown", artist: "Unknown")
        #expect(result == nil)
    }

    @Test("write then read returns stored Track")
    func writeAndReadRoundTrip() async throws {
        let store = try makeStore()
        let track = Track(title: "しゃぼん玉", artist: "大塚愛")
        try await store.write(title: "Shabondama", artist: "Ai Otsuka", value: track)
        let result = await store.read(title: "Shabondama", artist: "Ai Otsuka")
        #expect(result?.title == "しゃぼん玉")
        #expect(result?.artist == "大塚愛")
    }

    @Test("same key overwrites previous value")
    func sameKeyOverwrites() async throws {
        let store = try makeStore()
        try await store.write(title: "Song", artist: "Artist", value: Track(title: "V1", artist: "A1"))
        try await store.write(title: "Song", artist: "Artist", value: Track(title: "V2", artist: "A2"))
        let result = await store.read(title: "Song", artist: "Artist")
        #expect(result?.title == "V2")
        #expect(result?.artist == "A2")
    }

    @Test("different keys are independent")
    func differentKeysIndependent() async throws {
        let store = try makeStore()
        try await store.write(title: "A", artist: "X", value: Track(title: "TA", artist: "AX"))
        try await store.write(title: "B", artist: "Y", value: Track(title: "TB", artist: "BY"))
        let a = await store.read(title: "A", artist: "X")
        let b = await store.read(title: "B", artist: "Y")
        #expect(a?.title == "TA")
        #expect(b?.title == "TB")
    }
}
