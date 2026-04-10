import Dependencies
import Domain
import Foundation
import Testing

@testable import PlaybackUseCase

@Suite("PlaybackUseCase")
struct PlaybackUseCaseTests {
    @Test("yields NowPlaying values from repository stream")
    func yieldsValues() async {
        let now = Date()
        let infos: [NowPlaying?] = [
            NowPlaying(title: "Song", artist: "Artist", artworkData: nil, duration: 200, rawElapsed: 10, playbackRate: 1.0, timestamp: now),
            nil,
            NowPlaying(title: "Next", artist: "Band", artworkData: nil, duration: 180, rawElapsed: 0, playbackRate: 1.0, timestamp: now),
        ]
        await withDependencies {
            $0.nowPlayingRepository = MockNowPlayingRepository(infos: infos)
        } operation: {
            let useCase = PlaybackUseCaseImpl()
            var collected: [NowPlaying?] = []
            for await value in useCase.observeNowPlaying() {
                collected.append(value)
            }
            #expect(collected.count == infos.count)
            #expect(collected[0]?.title == "Song")
            #expect(collected[1] == nil)
            #expect(collected[2]?.title == "Next")
        }
    }

    // MARK: - fetchNowPlaying (one-shot)

    @Test("fetchNowPlaying returns first item from repository")
    func fetchReturnsFirst() async {
        let now = Date()
        let expected = NowPlaying(
            title: "Song", artist: "Artist", artworkData: nil,
            duration: 200, rawElapsed: 10, playbackRate: 1.0, timestamp: now
        )
        await withDependencies {
            $0.nowPlayingRepository = MockNowPlayingRepository(infos: [expected])
        } operation: {
            let useCase = PlaybackUseCaseImpl()
            let result = await useCase.fetchNowPlaying()
            #expect(result?.title == "Song")
            #expect(result?.artist == "Artist")
        }
    }

    @Test("fetchNowPlaying returns nil when repository is empty")
    func fetchReturnsNilWhenEmpty() async {
        await withDependencies {
            $0.nowPlayingRepository = MockNowPlayingRepository(infos: [])
        } operation: {
            let useCase = PlaybackUseCaseImpl()
            let result = await useCase.fetchNowPlaying()
            #expect(result == nil)
        }
    }

    // MARK: - observeNowPlaying (stream)

    @Test("finishes when repository stream is empty")
    func emptyStream() async {
        await withDependencies {
            $0.nowPlayingRepository = MockNowPlayingRepository(infos: [])
        } operation: {
            let useCase = PlaybackUseCaseImpl()
            var collected: [NowPlaying?] = []
            for await value in useCase.observeNowPlaying() {
                collected.append(value)
            }
            #expect(collected.isEmpty)
        }
    }
}

// MARK: - elapsedTime

@Test("elapsedTime returns nil when rawElapsed is nil")
func elapsedTimeNilRawElapsed() {
    let np = NowPlaying(
        title: "Song", artist: "Artist", artworkData: nil,
        duration: 200, rawElapsed: nil, playbackRate: 1.0, timestamp: Date()
    )
    withDependencies {
        $0.nowPlayingRepository = MockNowPlayingRepository(infos: [])
        $0.date.now = Date()
    } operation: {
        let useCase = PlaybackUseCaseImpl()
        #expect(useCase.elapsedTime(for: np) == nil)
    }
}

@Test("elapsedTime returns base when timestamp is nil")
func elapsedTimeNilTimestamp() {
    let np = NowPlaying(
        title: "Song", artist: "Artist", artworkData: nil,
        duration: 200, rawElapsed: 42.0, playbackRate: 1.0, timestamp: nil
    )
    withDependencies {
        $0.nowPlayingRepository = MockNowPlayingRepository(infos: [])
        $0.date.now = Date()
    } operation: {
        let useCase = PlaybackUseCaseImpl()
        #expect(useCase.elapsedTime(for: np) == 42.0)
    }
}

@Test("elapsedTime computes base + rate * elapsed since timestamp")
func elapsedTimeComputed() {
    let ts = Date(timeIntervalSinceReferenceDate: 1000)
    let now = Date(timeIntervalSinceReferenceDate: 1010)
    let np = NowPlaying(
        title: "Song", artist: "Artist", artworkData: nil,
        duration: 200, rawElapsed: 5.0, playbackRate: 1.0, timestamp: ts
    )
    withDependencies {
        $0.nowPlayingRepository = MockNowPlayingRepository(infos: [])
        $0.date.now = now
    } operation: {
        let useCase = PlaybackUseCaseImpl()
        let result = useCase.elapsedTime(for: np)
        // 5.0 + 1.0 * (1010 - 1000) = 15.0
        #expect(result == 15.0)
    }
}

@Test("elapsedTime respects playback rate")
func elapsedTimeWithRate() {
    let ts = Date(timeIntervalSinceReferenceDate: 1000)
    let now = Date(timeIntervalSinceReferenceDate: 1010)
    let np = NowPlaying(
        title: "Song", artist: "Artist", artworkData: nil,
        duration: 200, rawElapsed: 5.0, playbackRate: 2.0, timestamp: ts
    )
    withDependencies {
        $0.nowPlayingRepository = MockNowPlayingRepository(infos: [])
        $0.date.now = now
    } operation: {
        let useCase = PlaybackUseCaseImpl()
        let result = useCase.elapsedTime(for: np)
        // 5.0 + 2.0 * (1010 - 1000) = 25.0
        #expect(result == 25.0)
    }
}

// MARK: - Mocks

private struct MockNowPlayingRepository: NowPlayingRepository {
    let infos: [NowPlaying?]

    func fetch() async -> NowPlaying? { infos.first ?? nil }

    func stream() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            for info in infos { continuation.yield(info) }
            continuation.finish()
        }
    }
}
