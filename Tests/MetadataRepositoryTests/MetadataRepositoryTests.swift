import Dependencies
import Domain
import Foundation
import Testing
@testable import MetadataRepository

@Suite("MetadataRepository")
struct MetadataRepositoryTests {
    @Test("returns first non-empty normalizer result")
    func returnsFirstNonEmpty() async {
        let expected = [Track(title: "Resolved", artist: "Artist")]
        await withDependencies {
            $0.metadataDataSources = [
                StubNormalizer(candidates: expected),
                StubNormalizer(candidates: [Track(title: "Other", artist: "Other")]),
            ]
        } operation: {
            let repo = MetadataRepositoryImpl()
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == expected)
        }
    }

    @Test("skips empty normalizers and uses second")
    func skipsEmptyUsesSecond() async {
        let expected = [Track(title: "Fallback", artist: "B")]
        await withDependencies {
            $0.metadataDataSources = [
                StubNormalizer(candidates: []),
                StubNormalizer(candidates: expected),
            ]
        } operation: {
            let repo = MetadataRepositoryImpl()
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == expected)
        }
    }

    @Test("returns empty when all normalizers return empty")
    func allEmpty() async {
        await withDependencies {
            $0.metadataDataSources = [
                StubNormalizer(candidates: []),
                StubNormalizer(candidates: []),
            ]
        } operation: {
            let repo = MetadataRepositoryImpl()
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result.isEmpty)
        }
    }

    @Test("returns empty when no normalizers configured")
    func noNormalizers() async {
        await withDependencies {
            $0.metadataDataSources = []
        } operation: {
            let repo = MetadataRepositoryImpl()
            let result = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result.isEmpty)
        }
    }

    @Test("does not call second normalizer when first succeeds")
    func shortCircuits() async {
        let tracker = CallTracker()
        await withDependencies {
            $0.metadataDataSources = [
                StubNormalizer(candidates: [Track(title: "Hit", artist: "A")]),
                TrackingNormalizer(tracker: tracker),
            ]
        } operation: {
            let repo = MetadataRepositoryImpl()
            _ = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            let wasCalled = await tracker.called
            #expect(!wasCalled)
        }
    }
}

// MARK: - Mocks

private struct StubNormalizer: MetadataDataSource {
    let candidates: [Track]
    func resolve(track: Track) async -> [Track] { candidates }
}

private actor CallTracker {
    private(set) var called = false
    func markCalled() { called = true }
}

private struct TrackingNormalizer: MetadataDataSource {
    let tracker: CallTracker
    func resolve(track: Track) async -> [Track] {
        await tracker.markCalled()
        return []
    }
}
