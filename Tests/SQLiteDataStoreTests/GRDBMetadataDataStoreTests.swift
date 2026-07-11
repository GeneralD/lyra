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

    @Test("write then read returns all stored candidates in insertion order")
    func writeAndReadRoundTrip() async throws {
        let store = try makeStore()
        let candidates = [
            MusicBrainzMetadata(title: "Feel fine!", artist: "倉木麻衣", duration: 288.17, musicbrainzId: "abc-123"),
            MusicBrainzMetadata(title: "Feel fine! (single)", artist: "倉木麻衣", duration: 291.0, musicbrainzId: "def-456"),
        ]
        try await store.write(title: "Feel fine", artist: "Mai Kuraki", value: candidates)
        let result = await store.read(title: "Feel fine", artist: "Mai Kuraki")
        #expect(result?.count == 2)
        #expect(result?.first?.title == "Feel fine!")
        #expect(result?.first?.artist == "倉木麻衣")
        #expect(result?.first?.duration == 288.17)
        #expect(result?.first?.musicbrainzId == "abc-123")
        #expect(result?.last?.title == "Feel fine! (single)")
        #expect(result?.last?.musicbrainzId == "def-456")
    }

    @Test("same key overwrites the previous candidate set entirely")
    func sameKeyOverwrites() async throws {
        let store = try makeStore()
        let v1 = [
            MusicBrainzMetadata(title: "V1", artist: "A1", duration: nil, musicbrainzId: "id1"),
            MusicBrainzMetadata(title: "V1b", artist: "A1", duration: 200, musicbrainzId: "id1b"),
        ]
        let v2 = [MusicBrainzMetadata(title: "V2", artist: "A2", duration: 180, musicbrainzId: "id2")]
        try await store.write(title: "Song", artist: "Artist", value: v1)
        try await store.write(title: "Song", artist: "Artist", value: v2)
        let result = await store.read(title: "Song", artist: "Artist")
        #expect(result?.count == 1)
        #expect(result?.first?.title == "V2")
        #expect(result?.first?.musicbrainzId == "id2")
    }

    @Test("distinct keys keep independent candidate sets")
    func distinctKeysAreIndependent() async throws {
        let store = try makeStore()
        try await store.write(
            title: "Song A", artist: "Artist",
            value: [MusicBrainzMetadata(title: "A", artist: "X", duration: nil, musicbrainzId: "a")])
        try await store.write(
            title: "Song B", artist: "Artist",
            value: [MusicBrainzMetadata(title: "B", artist: "Y", duration: nil, musicbrainzId: "b")])
        let a = await store.read(title: "Song A", artist: "Artist")
        let b = await store.read(title: "Song B", artist: "Artist")
        #expect(a?.count == 1)
        #expect(a?.first?.title == "A")
        #expect(b?.count == 1)
        #expect(b?.first?.title == "B")
    }
}
