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

    // MARK: - fetch (one-shot)

    @Test("fetch returns NowPlaying when dataSource returns .info")
    func fetchReturnsInfo() async {
        let expected = NowPlaying(
            title: "One Shot", artist: "Artist", artworkData: nil,
            duration: 120, rawElapsed: 5, playbackRate: 1, timestamp: Date()
        )

        await withDependencies {
            $0.mediaRemoteDataSource = MockMediaRemoteDataSource(results: [.info(expected)])
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            let result = await repo.fetch()
            #expect(result?.title == "One Shot")
            #expect(result?.artist == "Artist")
        }
    }

    @Test("fetch returns nil when dataSource returns .noInfo")
    func fetchReturnsNilOnNoInfo() async {
        await withDependencies {
            $0.mediaRemoteDataSource = MockMediaRemoteDataSource(results: [.noInfo])
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            let result = await repo.fetch()
            #expect(result == nil)
        }
    }

    @Test("fetch returns nil when dataSource returns .eof")
    func fetchReturnsNilOnEof() async {
        await withDependencies {
            $0.mediaRemoteDataSource = MockMediaRemoteDataSource(results: [.eof])
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            let result = await repo.fetch()
            #expect(result == nil)
        }
    }

    // MARK: - stream

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

    // MARK: - multicast (#23)

    @Test("two subscribers both receive every event")
    func multicastTwoSubscribers() async {
        let track = NowPlaying(
            title: "Shared", artist: "Artist", artworkData: nil,
            duration: 100, rawElapsed: 0, playbackRate: 1, timestamp: Date()
        )
        let gate = GatedMediaRemoteDataSource()

        await withDependencies {
            $0.mediaRemoteDataSource = gate
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            let streamA = repo.stream()
            let streamB = repo.stream()
            let collectA = Task {
                await streamA.reduce(into: [NowPlaying?]()) { $0.append($1) }
            }
            let collectB = Task {
                await streamB.reduce(into: [NowPlaying?]()) { $0.append($1) }
            }

            gate.send(.info(track))
            gate.send(.noInfo)
            gate.send(.eof)

            let a = await collectA.value
            let b = await collectB.value
            #expect(a.count == 2)
            #expect(a[0]?.title == "Shared")
            #expect(a[1] == nil)
            #expect(b.count == 2)
            #expect(b[0]?.title == "Shared")
            #expect(b[1] == nil)
        }
    }

    @Test("late subscriber immediately receives the last value")
    func lateSubscriberReplay() async {
        let track = NowPlaying(
            title: "Replayed", artist: "Artist", artworkData: nil,
            duration: 100, rawElapsed: 0, playbackRate: 1, timestamp: Date()
        )
        let gate = GatedMediaRemoteDataSource()

        await withDependencies {
            $0.mediaRemoteDataSource = gate
        } operation: {
            let repo = NowPlayingRepositoryImpl()
            var iteratorA = repo.stream().makeAsyncIterator()
            gate.send(.info(track))
            // Once A observes the broadcast, the hub has cached it for replay.
            let first = await iteratorA.next()
            #expect(first??.title == "Replayed")

            var iteratorB = repo.stream().makeAsyncIterator()
            let replayed = await iteratorB.next()
            #expect(replayed??.title == "Replayed")

            gate.send(.eof)
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

/// Blocks `poll()` until the test feeds a result, so multicast tests control
/// exactly when the repository's pump observes each event. Only the single
/// pump consumes `iterator`, matching the live single-poller contract.
private final class GatedMediaRemoteDataSource: MediaRemoteDataSource, @unchecked Sendable {
    private var iterator: AsyncStream<MediaRemotePollResult>.AsyncIterator
    private let feed: AsyncStream<MediaRemotePollResult>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<MediaRemotePollResult>.makeStream()
        iterator = stream.makeAsyncIterator()
        feed = continuation
    }

    func send(_ result: MediaRemotePollResult) {
        feed.yield(result)
    }

    func poll() async -> MediaRemotePollResult {
        await iterator.next() ?? .eof
    }
}
