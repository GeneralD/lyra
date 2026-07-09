import Dependencies
import Domain
import Foundation
import Testing

@testable import MetadataRepository

// MARK: - Cache behavior

@Suite("LLM cache")
struct LLMCacheTests {
    @Test("cache hit still queries MusicBrainz and Regex, raw track appended last")
    func cacheHitStillQueriesOtherSources() async {
        let cached = Track(title: "Cached", artist: "Artist")
        let mbTracker = CallTracker()
        let regexTracker = CallTracker()

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore(result: cached)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = TrackingDataSource<MusicBrainzMetadata>(tracker: mbTracker)
            $0.regexMetadataDataSource = TrackingDataSource<Track>(tracker: regexTracker)
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [cached, raw])
            let mbCalled = await mbTracker.called
            let regexCalled = await regexTracker.called
            #expect(mbCalled, "MusicBrainz must still be queried even when the LLM cache hits")
            #expect(regexCalled, "Regex must still be queried even when the LLM cache hits")
        }
    }
}

@Suite("MusicBrainz cache")
struct MusicBrainzCacheTests {
    @Test("returns cached MusicBrainzMetadata converted to Track, still queries Regex, raw appended")
    func mbCacheHitAfterLLMFail() async {
        let metadata = MusicBrainzMetadata(title: "MB Title", artist: "MB Artist", duration: 240, musicbrainzId: "abc-123")

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore(result: metadata)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [Track(title: "MB Title", artist: "MB Artist", duration: 240), raw])
        }
    }
}

// MARK: - DataSource merging

@Suite("DataSource merging")
struct DataSourceMergingTests {
    @Test("all sources are queried and merged in LLM > MusicBrainz > Regex > raw order")
    func allSourcesQueriedAndMerged() async {
        let mbMetadata = MusicBrainzMetadata(title: "MB", artist: "B", duration: nil, musicbrainzId: "id-1")

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource(candidates: [Track(title: "LLM", artist: "A")])
            $0.musicBrainzMetadataDataSource = StubDataSource(candidates: [mbMetadata])
            $0.regexMetadataDataSource = StubDataSource(candidates: [Track(title: "Regex", artist: "C")])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(
                result == [
                    Track(title: "LLM", artist: "A"),
                    Track(title: "MB", artist: "B"),
                    Track(title: "Regex", artist: "C"),
                    raw,
                ])
        }
    }

    @Test("falls back to Regex when LLM and MusicBrainz both fail, raw still appended")
    func regexFallback() async {
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource(candidates: [Track(title: "Regex", artist: "C")])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [Track(title: "Regex", artist: "C"), raw])
        }
    }

    @Test("raw track is the sole result when all sources fail")
    func rawOnlyWhenAllSourcesFail() async {
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [raw])
        }
    }
}

// MARK: - Cache write behavior

@Suite("cache write")
struct CacheWriteTests {
    @Test("LLM success writes to AI cache")
    func llmWritesToAICache() async {
        let store = RecordingDataStore<Track>()

        await withDependencies {
            $0.llmMetadataDataStore = store
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource(candidates: [Track(title: "LLM", artist: "A")])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            _ = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            let written = await store.writtenValue
            #expect(written == Track(title: "LLM", artist: "A"))
        }
    }

    @Test("MusicBrainz success writes to MusicBrainz cache")
    func mbWritesToMBCache() async {
        let store = RecordingDataStore<MusicBrainzMetadata>()
        let metadata = MusicBrainzMetadata(title: "Song", artist: "B", duration: 180, musicbrainzId: "xyz")

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = store
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource(candidates: [metadata])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            _ = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            let written = await store.writtenValue
            #expect(written == metadata)
        }
    }

    @Test("Regex results are not cached")
    func regexNotCached() async {
        let aiStore = RecordingDataStore<Track>()
        let mbStore = RecordingDataStore<MusicBrainzMetadata>()

        await withDependencies {
            $0.llmMetadataDataStore = aiStore
            $0.musicBrainzMetadataDataStore = mbStore
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource(candidates: [Track(title: "Regex", artist: "C")])
        } operation: {
            let repo = MetadataRepositoryImpl()
            _ = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            let aiWritten = await aiStore.writtenValue
            let mbWritten = await mbStore.writtenValue
            #expect(aiWritten == nil)
            #expect(mbWritten == nil)
        }
    }
}

// MARK: - Type conversion

@Suite("type conversion")
struct TypeConversionTests {
    @Test("MusicBrainzMetadata converts to Track using title and artist only, raw appended")
    func mbToTrackConversion() async {
        let metadata = MusicBrainzMetadata(title: "Song", artist: "Artist", duration: 300, musicbrainzId: "id-999")

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource(candidates: [metadata])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [Track(title: "Song", artist: "Artist", duration: 300), raw])
        }
    }
}

// MARK: - isAIMetadataCached

@Suite("isAIMetadataCached")
struct IsAIMetadataCachedTests {
    @Test("returns true when the LLM cache holds a value")
    func cachedReturnsTrue() async {
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore(result: Track(title: "Cached", artist: "Artist"))
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let cached = await repo.isAIMetadataCached(track: Track(title: "raw", artist: "raw"))
            #expect(cached)
        }
    }

    @Test("returns false when the LLM cache is empty — no DataSource is consulted")
    func uncachedReturnsFalse() async {
        let llmTracker = CallTracker()
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = TrackingDataSource<Track>(tracker: llmTracker)
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let cached = await repo.isAIMetadataCached(track: Track(title: "raw", artist: "raw"))
            #expect(!cached)
            let llmCalled = await llmTracker.called
            #expect(!llmCalled, "isAIMetadataCached must only read the cache, never invoke the DataSource")
        }
    }
}

// MARK: - Test helpers

private struct StubMetadataDataStore<Value: Sendable & Equatable>: MetadataDataStore {
    let result: Value?
    func read(title: String, artist: String) async -> Value? { result }
    func write(title: String, artist: String, value: Value) async throws {}
}

private actor RecordingDataStore<Value: Sendable & Equatable>: MetadataDataStore {
    private(set) var writtenValue: Value?
    func read(title: String, artist: String) async -> Value? { nil }
    func write(title: String, artist: String, value: Value) async throws { writtenValue = value }
}

private struct StubDataSource<Value: Sendable>: MetadataDataSource {
    let candidates: [Value]
    func resolve(track: Track) async -> [Value] { candidates }
}

private actor CallTracker {
    private(set) var called = false
    func markCalled() { called = true }
}

private struct TrackingDataSource<Value: Sendable>: MetadataDataSource {
    let tracker: CallTracker
    func resolve(track: Track) async -> [Value] {
        await tracker.markCalled()
        return []
    }
}
