import Dependencies
import Domain
import Foundation
import Testing

@testable import MetadataRepository

// MARK: - Cache behavior

@Suite("LLM cache")
struct LLMCacheTests {
    @Test("returns cached Track without calling any DataSource")
    func cacheHitSkipsDataSources() async {
        let cached = Track(title: "Cached", artist: "Artist")
        let llmTracker = CallTracker()
        let mbTracker = CallTracker()
        let regexTracker = CallTracker()

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore(result: cached)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = TrackingDataSource<Track>(tracker: llmTracker)
            $0.musicBrainzMetadataDataSource = TrackingDataSource<MusicBrainzMetadata>(tracker: mbTracker)
            $0.regexMetadataDataSource = TrackingDataSource<Track>(tracker: regexTracker)
        } operation: {
            let repo = MetadataRepositoryImpl()
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == [cached])
            let llmCalled = await llmTracker.called
            let mbCalled = await mbTracker.called
            let regexCalled = await regexTracker.called
            #expect(!llmCalled)
            #expect(!mbCalled)
            #expect(!regexCalled)
        }
    }
}

@Suite("MusicBrainz cache")
struct MusicBrainzCacheTests {
    @Test("returns cached MusicBrainzMetadata converted to Track when LLM fails")
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
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == [Track(title: "MB Title", artist: "MB Artist", duration: 240)])
        }
    }
}

// MARK: - DataSource priority

@Suite("DataSource priority")
struct DataSourcePriorityTests {
    @Test("LLM success skips MusicBrainz and Regex")
    func llmSuccessShortCircuits() async {
        let mbTracker = CallTracker()
        let regexTracker = CallTracker()

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource(candidates: [Track(title: "LLM", artist: "A")])
            $0.musicBrainzMetadataDataSource = TrackingDataSource<MusicBrainzMetadata>(tracker: mbTracker)
            $0.regexMetadataDataSource = TrackingDataSource<Track>(tracker: regexTracker)
        } operation: {
            let repo = MetadataRepositoryImpl()
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == [Track(title: "LLM", artist: "A")])
            let mbCalled = await mbTracker.called
            let regexCalled = await regexTracker.called
            #expect(!mbCalled)
            #expect(!regexCalled)
        }
    }

    @Test("MusicBrainz success skips Regex")
    func mbSuccessSkipsRegex() async {
        let regexTracker = CallTracker()
        let metadata = MusicBrainzMetadata(title: "MB", artist: "B", duration: nil, musicbrainzId: "id-1")

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource(candidates: [metadata])
            $0.regexMetadataDataSource = TrackingDataSource<Track>(tracker: regexTracker)
        } operation: {
            let repo = MetadataRepositoryImpl()
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == [Track(title: "MB", artist: "B")])
            let regexCalled = await regexTracker.called
            #expect(!regexCalled)
        }
    }

    @Test("falls back to Regex when LLM and MusicBrainz both fail")
    func regexFallback() async {
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource(candidates: [Track(title: "Regex", artist: "C")])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == [Track(title: "Regex", artist: "C")])
        }
    }

    @Test("returns empty when all sources fail")
    func allEmpty() async {
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result.isEmpty)
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
    @Test("MusicBrainzMetadata converts to Track using title and artist only")
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
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == [Track(title: "Song", artist: "Artist", duration: 300)])
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
