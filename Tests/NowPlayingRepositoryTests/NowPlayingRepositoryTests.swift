import Dependencies
import Domain
import Foundation
import Testing

@testable import NowPlayingRepository

@Suite("NowPlayingRepository")
struct NowPlayingRepositoryTests {

    @Test("yields NowPlaying when dataSource returns .info")
    func yieldsNowPlaying() async {
        let expected = NowPlaying(
            title: "Numb", artist: "Linkin Park", artworkData: nil,
            duration: 187, rawElapsed: 30, playbackRate: 1, timestamp: Date()
        )

        await withDependencies {
            $0.mediaRemoteDataSource = MockMediaRemoteDataSource(results: [.info(expected), .eof])
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            var collected: [NowPlaying?] = []
            for await info in repo.stream() {
                collected.append(info)
            }
            #expect(collected.count == 1)
            #expect(collected[0]?.title == "Numb")
            #expect(collected[0]?.artist == "Linkin Park")
        }
    }

    @Test("yields nil when dataSource returns .noInfo")
    func yieldsNilOnNoInfo() async {
        await withDependencies {
            $0.mediaRemoteDataSource = MockMediaRemoteDataSource(results: [.noInfo, .eof])
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            var collected: [NowPlaying?] = []
            for await info in repo.stream() {
                collected.append(info)
            }
            #expect(collected.count == 1)
            #expect(collected[0] == nil)
        }
    }

    @Test("finishes stream when dataSource returns .eof")
    func finishesOnEof() async {
        await withDependencies {
            $0.mediaRemoteDataSource = MockMediaRemoteDataSource(results: [.eof])
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            var count = 0
            for await _ in repo.stream() {
                count += 1
            }
            #expect(count == 0)
        }
    }

    @Test("yields multiple items in order before eof")
    func multipleItemsInOrder() async {
        let track1 = NowPlaying(
            title: "Song A", artist: "Artist A", artworkData: nil,
            duration: 100, rawElapsed: 0, playbackRate: 1, timestamp: Date()
        )
        let track2 = NowPlaying(
            title: "Song B", artist: "Artist B", artworkData: nil,
            duration: 200, rawElapsed: 0, playbackRate: 1, timestamp: Date()
        )

        await withDependencies {
            $0.mediaRemoteDataSource = MockMediaRemoteDataSource(results: [.info(track1), .noInfo, .info(track2), .eof])
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            var collected: [NowPlaying?] = []
            for await info in repo.stream() {
                collected.append(info)
            }
            #expect(collected.count == 3)
            #expect(collected[0]?.title == "Song A")
            #expect(collected[1] == nil)
            #expect(collected[2]?.title == "Song B")
        }
    }

    @Test("all NowPlaying fields are forwarded from dataSource")
    func allFieldsForwarded() async {
        let artworkData = "fake-image".data(using: .utf8)
        let timestamp = Date(timeIntervalSinceReferenceDate: 1000)
        let expected = NowPlaying(
            title: "Title", artist: "Artist", artworkData: artworkData,
            duration: 300, rawElapsed: 42.5, playbackRate: 0.5, timestamp: timestamp
        )

        await withDependencies {
            $0.mediaRemoteDataSource = MockMediaRemoteDataSource(results: [.info(expected), .eof])
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            var result: NowPlaying?
            for await info in repo.stream() {
                result = info
            }
            #expect(result?.title == "Title")
            #expect(result?.artist == "Artist")
            #expect(result?.artworkData == artworkData)
            #expect(result?.duration == 300)
            #expect(result?.rawElapsed == 42.5)
            #expect(result?.playbackRate == 0.5)
            #expect(result?.timestamp == timestamp)
        }
    }
}

// MARK: - Mock

private final class MockMediaRemoteDataSource: MediaRemoteDataSource, @unchecked Sendable {
    private var results: [MediaRemotePollResult]
    private var index = 0

    init(results: [MediaRemotePollResult]) {
        self.results = results
    }

    func poll() async -> MediaRemotePollResult {
        guard index < results.count else { return .eof }
        let result = results[index]
        index += 1
        return result
    }
}
