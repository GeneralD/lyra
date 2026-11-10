import Dependencies
import Domain
import Foundation
import Testing

@testable import MediaRemoteDataSource

/// Client selection and per-client artwork as seen through `poll()` (#358): the
/// helper reports every now-playing client, and the data source follows the one
/// that is actually playing instead of trusting the system-designated slot.
@Suite("MediaRemoteDataSourceImpl client selection", .timeLimit(.minutes(1)))
struct MediaRemoteDataSourceSelectionTests {
    private let displayLink = clientEntry(
        bundleID: "com.displaylink.DisplayLinkUserAgent", pid: 1, title: nil, artist: nil, rate: 0)

    private func polled(_ lines: [String], decoder: CountingDecoder = CountingDecoder()) async
        -> [MediaRemotePollResult]
    {
        await withDependencies {
            $0.processGateway = StreamingGateway(streamPlans: [lines])
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(decodeBase64: decoder.decode)
            return await lines.asyncMap { _ in await dataSource.poll() }
        }
    }

    private func nowPlaying(_ result: MediaRemotePollResult) -> NowPlaying? {
        guard case .info(let nowPlaying) = result else { return nil }
        return nowPlaying
    }

    @Test("follows a playing client while a title-less app holds the system slot (#358)")
    func followsPlayingClientBehindHijackedSlot() async throws {
        let results = await polled([
            frameLine(
                systemPid: 1,
                clients: [
                    displayLink,
                    clientEntry(bundleID: "com.google.Chrome", pid: 2, title: "Song", artist: "Artist"),
                ])
        ])

        let info = try #require(nowPlaying(results[0]))
        #expect(info.title == "Song")
        #expect(info.artist == "Artist")
        // The spectrum tap must follow the same client as the lyrics (#23).
        #expect(info.pid == 2)
    }

    @Test("keeps following the chosen client across polls")
    func followedClientPersistsAcrossPolls() async {
        let results = await polled([
            frameLine(clients: [clientEntry(bundleID: "b.player", title: "B", timestamp: 1)]),
            frameLine(clients: [
                clientEntry(bundleID: "a.player", title: "A", timestamp: 99),
                clientEntry(bundleID: "b.player", title: "B", timestamp: 2),
            ]),
        ])

        #expect(results.map { nowPlaying($0)?.title } == ["B", "B"])
    }

    @Test("a frame without candidates does not forget the followed client")
    func emptyFrameKeepsFollowedClient() async {
        let results = await polled([
            frameLine(clients: [clientEntry(bundleID: "b.player", title: "B", timestamp: 1)]),
            frameLine(systemPid: 1, clients: [displayLink]),
            frameLine(clients: [
                clientEntry(bundleID: "a.player", title: "A", timestamp: 99),
                clientEntry(bundleID: "b.player", title: "B", timestamp: 2),
            ]),
        ])

        #expect(results.map { nowPlaying($0)?.title } == ["B", nil, "B"])
        guard case .noInfo = results[1] else {
            Issue.record("Expected .noInfo for the candidate-less frame, got \(results[1])")
            return
        }
    }

    @Test("a paused followed client is reported paused while the slot stays hijacked")
    func pausedFollowedClientIsReportedPaused() async throws {
        let results = await polled([
            frameLine(
                systemPid: 1,
                clients: [displayLink, clientEntry(bundleID: "com.google.Chrome", pid: 2, title: "Song")]),
            frameLine(
                systemPid: 1,
                clients: [
                    displayLink,
                    clientEntry(bundleID: "com.google.Chrome", pid: 2, title: "Song", rate: 0, timestamp: 1),
                    clientEntry(bundleID: "other.player", pid: 3, title: "Other", rate: 0, timestamp: 99),
                ]),
        ])

        let paused = try #require(nowPlaying(results[1]))
        #expect(paused.title == "Song")
        #expect(paused.playbackRate == 0)
    }

    @Test("switching clients serves the new client's cover without a resend")
    func switchingClientsReusesPerClientCover() async throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let decoder = CountingDecoder()

        let results = await polled(
            [
                frameLine(
                    systemPid: 1,
                    clients: [
                        clientEntry(
                            bundleID: "a.player", pid: 1, title: "A", artworkDigest: "da",
                            artworkBase64: first.base64EncodedString()),
                        clientEntry(
                            bundleID: "b.player", pid: 2, title: "B", rate: 0, artworkDigest: "db",
                            artworkBase64: second.base64EncodedString()),
                    ]),
                frameLine(
                    systemPid: 1,
                    clients: [
                        clientEntry(bundleID: "a.player", pid: 1, title: nil, rate: 0),
                        clientEntry(bundleID: "b.player", pid: 2, title: "B", artworkDigest: "db"),
                    ]),
            ], decoder: decoder)

        #expect(results.map { nowPlaying($0)?.title } == ["A", "B"])
        #expect(results.map { nowPlaying($0)?.artworkData } == [first, second])
        #expect(decoder.count == 2)
    }

    @Test("an unchanged cover digest is decoded once across frames (#255, #270)")
    func unchangedDigestDecodedOnce() async {
        let cover = Data("cover".utf8)
        let decoder = CountingDecoder()

        let results = await polled(
            [
                frameLine(clients: [
                    clientEntry(artworkDigest: "d1", artworkBase64: cover.base64EncodedString())
                ]),
                frameLine(clients: [clientEntry(artworkDigest: "d1")]),
            ], decoder: decoder)

        #expect(results.map { nowPlaying($0)?.artworkData } == [cover, cover])
        #expect(decoder.count == 1)
    }
}
