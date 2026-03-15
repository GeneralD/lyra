import Dependencies
import Foundation
import Testing
@testable import BackdropDomain
@testable import BackdropPresentation

@Suite("OverlayController")
struct OverlayControllerTests {

    @Test("track change sets title and artist")
    @MainActor
    func trackChangeReveals() async throws {
        await withDependencies {
            $0.nowPlayingProvider = MockNowPlayingProvider(infos: [
                makeNowPlaying(title: "Numb", artist: "Linkin Park"),
            ])
            $0.lyricsRepository = MockLyricsRepository(result: nil)
            $0.lyricsCache = MockLyricsCache()
            $0.metadataCache = MockMetadataCache()
            $0.config = .init()
        } operation: {
            let controller = OverlayController()
            controller.start()
            try? await Task.sleep(for: .milliseconds(300))
            controller.stop()

            #expect(controller.state.title.value == "Numb")
            #expect(controller.state.artist.value == "Linkin Park")
        }
    }

    @Test("nil title sets state to idle")
    @MainActor
    func nilTitleSetsIdle() async throws {
        await withDependencies {
            $0.nowPlayingProvider = MockNowPlayingProvider(infos: [
                makeNowPlaying(title: nil, artist: nil),
            ])
            $0.lyricsRepository = MockLyricsRepository(result: nil)
            $0.lyricsCache = MockLyricsCache()
            $0.metadataCache = MockMetadataCache()
            $0.config = .init()
        } operation: {
            let controller = OverlayController()
            controller.start()
            try? await Task.sleep(for: .milliseconds(300))
            controller.stop()

            #expect(controller.state.title.isIdle)
            #expect(controller.state.artist.isIdle)
        }
    }

    @Test("lyrics set to failure when not found")
    @MainActor
    func lyricsFailure() async throws {
        await withDependencies {
            $0.nowPlayingProvider = MockNowPlayingProvider(infos: [
                makeNowPlaying(title: "Unknown", artist: "Nobody"),
            ])
            $0.lyricsRepository = MockLyricsRepository(result: nil)
            $0.lyricsCache = MockLyricsCache()
            $0.metadataCache = MockMetadataCache()
            $0.config = .init()
        } operation: {
            let controller = OverlayController()
            controller.start()
            try? await Task.sleep(for: .milliseconds(500))
            controller.stop()

            guard case .failure = controller.state.lyrics else {
                #expect(Bool(false), "Expected .failure but got \(controller.state.lyrics)")
                return
            }
        }
    }

    @Test("stream nil after track clears state")
    @MainActor
    func streamNilClearsState() async throws {
        await withDependencies {
            $0.nowPlayingProvider = MockNowPlayingProvider(infos: [
                makeNowPlaying(title: "Song", artist: "Artist"),
                nil,
            ])
            $0.lyricsRepository = MockLyricsRepository(result: nil)
            $0.lyricsCache = MockLyricsCache()
            $0.metadataCache = MockMetadataCache()
            $0.config = .init()
        } operation: {
            let controller = OverlayController()
            controller.start()
            try? await Task.sleep(for: .milliseconds(500))
            controller.stop()

            #expect(controller.state.title.isIdle)
            #expect(controller.state.lyrics.isIdle)
        }
    }

    @Test("rapid track changes discard stale fetch")
    @MainActor
    func generationCancellation() async throws {
        await withDependencies {
            $0.nowPlayingProvider = MockNowPlayingProvider(infos: [
                makeNowPlaying(title: "First", artist: "A"),
                makeNowPlaying(title: "Second", artist: "B"),
            ])
            $0.lyricsRepository = MockLyricsRepository(result: LyricsResult(
                trackName: "Second Track", artistName: "B"
            ))
            $0.lyricsCache = MockLyricsCache()
            $0.metadataCache = MockMetadataCache()
            $0.config = .init()
        } operation: {
            let controller = OverlayController()
            controller.start()
            try? await Task.sleep(for: .milliseconds(500))
            controller.stop()

            #expect(controller.state.title.value == "Second Track" || controller.state.title.value == "Second")
        }
    }
}

// MARK: - Helpers

private func makeNowPlaying(title: String?, artist: String?) -> NowPlaying {
    NowPlaying(
        title: title, artist: artist, artworkData: nil,
        duration: 200, rawElapsed: 0, playbackRate: 1, timestamp: Date()
    )
}

// MARK: - Mocks

private struct MockNowPlayingProvider: NowPlayingProvider {
    let infos: [NowPlaying?]

    func stream() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            for info in infos {
                continuation.yield(info)
            }
            continuation.finish()
        }
    }
}

private struct MockLyricsRepository: LyricsRepository {
    let result: LyricsResult?

    func fetch(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        result
    }
}

private struct MockLyricsCache: LyricsCacheRepository {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

private struct MockMetadataCache: MetadataCacheRepository {
    func read(title: String, artist: String) async -> ResolvedMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: ResolvedMetadata) async throws {}
}
