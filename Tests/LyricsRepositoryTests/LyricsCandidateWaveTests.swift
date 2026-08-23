import Dependencies
import Domain
import Foundation
import Testing

@testable import LyricsRepository

// The serial candidate loop cost N network round-trips per tier; probing in waves cuts
// that to ceil(N / waveSize). These tests pin the two properties that make the trade
// safe: a wave still yields the *highest-priority* hit, and a wave that hits never
// reaches the next one (#326).
@Suite("candidate wave probing (#326)")
struct LyricsCandidateWaveTests {

    @Test("the highest-priority candidate wins even when a lower-priority one also matches")
    func highestPriorityCandidateWinsWithinAWave() async {
        // Both candidates sit in the same wave and are probed concurrently, so the winner
        // must come from the candidate order, never from which request returned first.
        let source = RecordingLyricsDataSource(hits: ["Preferred": "preferred lyrics", "Fallback": "fallback lyrics"])
        let cache = WriteKeyCapturingCache()

        await withDependencies {
            $0.lyricsCache = cache
            $0.lyricsDataSource = source
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(candidates: [
                Track(title: "Preferred", artist: "Artist"),
                Track(title: "Fallback", artist: "Artist"),
            ])
            #expect(result?.plainLyrics == "preferred lyrics")
        }
        #expect(await cache.writtenTitles == ["Preferred"])
    }

    @Test("a wave that hits never probes the next wave")
    func aHitStopsBeforeTheNextWave() async {
        let source = RecordingLyricsDataSource(hits: ["c0": "lyrics"])

        await withDependencies {
            $0.lyricsCache = NoopCache()
            $0.lyricsDataSource = source
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(
                candidates: (0..<6).map { Track(title: "c\($0)", artist: "Artist") })
            #expect(result?.plainLyrics == "lyrics")
        }

        // Wave 1 (c0…c3) is probed concurrently — that over-fetch is the price of dropping
        // from N round-trips to one. Wave 2 (c4, c5) must never be reached.
        #expect(await source.probed.sorted() == ["c0", "c1", "c2", "c3"])
    }

    @Test("candidates within a wave are probed concurrently, not one at a time")
    func candidatesWithinAWaveOverlap() async {
        // Each probe parks until it sees its wave-mates in flight (or a deadline passes),
        // so a serial implementation records a maximum overlap of 1 and fails here.
        let source = ConcurrencyProbingDataSource(expected: 4)

        await withDependencies {
            $0.lyricsCache = NoopCache()
            $0.lyricsDataSource = source
        } operation: {
            let repo = LyricsRepositoryImpl()
            _ = await repo.fetchLyrics(candidates: (0..<4).map { Track(title: "c\($0)", artist: "Artist") })
        }

        #expect(await source.maxConcurrent == 4)
    }

    @Test("a hit in a later wave is still found once every earlier wave misses")
    func laterWaveHitIsStillReached() async {
        let source = RecordingLyricsDataSource(hits: ["c5": "late lyrics"])

        await withDependencies {
            $0.lyricsCache = NoopCache()
            $0.lyricsDataSource = source
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(
                candidates: (0..<6).map { Track(title: "c\($0)", artist: "Artist") })
            #expect(result?.plainLyrics == "late lyrics")
        }
        #expect(await source.probed.count == 6)
    }
}

// MARK: - Test doubles

// Returns lyrics for the titles in `hits` and records every title it was asked about.
private actor RecordingLyricsDataSource: LyricsDataSource {
    private let hits: [String: String]
    private(set) var probed: [String] = []

    init(hits: [String: String]) { self.hits = hits }

    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        probed.append(title)
        guard let lyrics = hits[title] else { return nil }
        return LyricsResult(trackName: title, artistName: artist, plainLyrics: lyrics)
    }

    func search(query: String) async -> [LyricsResult]? { nil }
}

// Records the peak number of overlapping `get` calls. Each call parks until either the
// whole wave has arrived or the deadline expires, so the peak reflects real overlap
// without a fixed sleep that would be flaky under CI load.
private actor ConcurrencyProbingDataSource: LyricsDataSource {
    private let expected: Int
    private var inFlight = 0
    // Latched once the whole wave has arrived, so callers that already saw it are not
    // re-parked by their wave-mates draining away.
    private var waveArrived = false
    private(set) var maxConcurrent = 0

    init(expected: Int) { self.expected = expected }

    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        inFlight += 1
        maxConcurrent = max(maxConcurrent, inFlight)
        waveArrived = waveArrived || inFlight >= expected
        let deadline = ContinuousClock.now + .seconds(3)
        while !waveArrived, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        inFlight -= 1
        return nil
    }

    func search(query: String) async -> [LyricsResult]? { nil }
}

private actor WriteKeyCapturingCache: LyricsDataStore {
    private(set) var writtenTitles: [String] = []
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {
        writtenTitles.append(title)
    }
}

private struct NoopCache: LyricsDataStore {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}
