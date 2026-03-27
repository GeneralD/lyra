import Domain
import Testing

@testable import SQLiteDataStore

@Suite("GRDBMetadataDataStore")
struct GRDBMetadataDataStoreTests {
    private func makeStore() throws -> GRDBMetadataDataStore {
        GRDBMetadataDataStore(dbManager: try DatabaseManager(inMemory: true))
    }

    @Test("read returns nil for unknown key")
    func readReturnsNil() async throws {
        let store = try makeStore()
        let result = await store.read(title: "Unknown", artist: "Unknown")
        #expect(result == nil)
    }

    @Test("write then read returns stored MusicBrainzMetadata")
    func writeAndReadRoundTrip() async throws {
        let store = try makeStore()
        let metadata = MusicBrainzMetadata(
            title: "Feel fine!", artist: "倉木麻衣", duration: 288.17, musicbrainzId: "abc-123")
        try await store.write(title: "Feel fine", artist: "Mai Kuraki", value: metadata)
        let result = await store.read(title: "Feel fine", artist: "Mai Kuraki")
        #expect(result?.title == "Feel fine!")
        #expect(result?.artist == "倉木麻衣")
        #expect(result?.duration == 288.17)
        #expect(result?.musicbrainzId == "abc-123")
    }

    @Test("same key overwrites previous value")
    func sameKeyOverwrites() async throws {
        let store = try makeStore()
        let v1 = MusicBrainzMetadata(title: "V1", artist: "A1", duration: nil, musicbrainzId: "id1")
        let v2 = MusicBrainzMetadata(title: "V2", artist: "A2", duration: 180, musicbrainzId: "id2")
        try await store.write(title: "Song", artist: "Artist", value: v1)
        try await store.write(title: "Song", artist: "Artist", value: v2)
        let result = await store.read(title: "Song", artist: "Artist")
        #expect(result?.title == "V2")
        #expect(result?.musicbrainzId == "id2")
    }
}
