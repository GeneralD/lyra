import Dependencies
import Domain
import Foundation
import TestSupport
import Testing

@testable import MediaRemoteDataSource

@Suite("MediaRemoteDataSourceImpl", .timeLimit(.minutes(1)))
struct MediaRemoteDataSourceImplTests {
    @Test("poll returns info for a frame with a titled client")
    func pollReturnsInfo() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [frameLine(clients: [clientEntry(title: "Song", artist: "Artist")])]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl()
            let result = await dataSource.poll()

            guard case .info(let nowPlaying) = result else {
                Issue.record("Expected .info, got \(result)")
                return
            }
            #expect(nowPlaying.title == "Song")
            #expect(nowPlaying.artist == "Artist")
        }
    }

    @Test("poll maps every field of the selected client onto NowPlaying")
    func pollMapsAllFields() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [
                frameLine(clients: [
                    clientEntry(
                        pid: 4242, title: "Song", artist: "Artist", duration: 200.0, elapsed: 12.5,
                        rate: 0.5, timestamp: 700.0)
                ])
            ]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let result = await MediaRemoteDataSourceImpl().poll()

            guard case .info(let nowPlaying) = result else {
                Issue.record("Expected .info, got \(result)")
                return
            }
            #expect(
                nowPlaying
                    == NowPlaying(
                        title: "Song", artist: "Artist", artworkData: nil, duration: 200.0,
                        rawElapsed: 12.5, playbackRate: 0.5,
                        timestamp: Date(timeIntervalSinceReferenceDate: 700.0), pid: 4242))
        }
    }

    @Test("a client without a reported rate or timestamp plays at 1x from the moment it was read")
    func missingRateAndTimestampAreFilledIn() async throws {
        let readAt = Date(timeIntervalSinceReferenceDate: 1_234.0)
        let gateway = StreamingGateway(streamPlans: [
            [frameLine(clients: [clientEntry(rate: nil, timestamp: nil)])]
        ])

        await withDependencies {
            $0.processGateway = gateway
            $0.date = .constant(readAt)
        } operation: {
            let result = await MediaRemoteDataSourceImpl().poll()

            guard case .info(let nowPlaying) = result else {
                Issue.record("Expected .info, got \(result)")
                return
            }
            #expect(nowPlaying.playbackRate == 1.0)
            // Without a timestamp `PlaybackUseCase` could not interpolate elapsed.
            #expect(nowPlaying.timestamp == readAt)
        }
    }

    @Test("the default decoder turns a cover payload into its bytes")
    func defaultDecoderDecodesCover() async throws {
        let cover = Data("cover".utf8)
        let gateway = StreamingGateway(streamPlans: [
            [frameLine(clients: [clientEntry(artworkDigest: "d1", artworkBase64: cover.base64EncodedString())])]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let result = await MediaRemoteDataSourceImpl().poll()

            guard case .info(let nowPlaying) = result else {
                Issue.record("Expected .info, got \(result)")
                return
            }
            #expect(nowPlaying.artworkData == cover)
        }
    }

    @Test("poll returns noInfo when no client carries a title")
    func pollReturnsNoInfo() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [frameLine(systemPid: 1, clients: [clientEntry(pid: 1, title: nil, rate: 0)])]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let result = await MediaRemoteDataSourceImpl().poll()
            guard case .noInfo = result else {
                Issue.record("Expected .noInfo, got \(result)")
                return
            }
        }
    }

    @Test(
        "poll returns noInfo for lines that are not a frame",
        arguments: ["{not-json}", "", #"{"has_info":true,"title":"Song"}"#])
    func pollReturnsNoInfoForMalformedLine(line: String) async throws {
        let gateway = StreamingGateway(streamPlans: [[line]])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let result = await MediaRemoteDataSourceImpl().poll()
            guard case .noInfo = result else {
                Issue.record("Expected .noInfo, got \(result)")
                return
            }
        }
    }

    @Test("poll restarts stream after eof")
    func pollRestartsAfterEof() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [],
            [frameLine(clients: [clientEntry(title: "Restarted")])],
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl()
            let first = await dataSource.poll()
            guard case .eof = first else {
                Issue.record("Expected initial .eof, got \(first)")
                return
            }

            let result = await dataSource.poll()
            guard case .info(let nowPlaying) = result else {
                Issue.record("Expected .info after restart, got \(result)")
                return
            }
            #expect(nowPlaying.title == "Restarted")
            #expect(gateway.runStreamingCallCount == 2)
        }
    }

    @Test("concurrent polls serialize iterator access")
    @available(macOS 15, *)
    func concurrentPollsSerializeIteratorAccess() async throws {
        let firstLineGate = Collector<Void>()
        let secondPollExecutor = ProbingExecutor()
        let gateway = StreamingGateway(
            streamPlans: [
                [
                    frameLine(clients: [clientEntry(title: "First")]),
                    frameLine(clients: [clientEntry(title: "Second")]),
                ]
            ],
            firstLineGate: firstLineGate
        )

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl()
            let results = await withTaskGroup(of: MediaRemotePollResult.self) { group in
                group.addTask { await dataSource.poll() }
                // The first poll is now inside `next()` on the shared iterator and stays
                // there until the gate opens.
                await gateway.nextRequests.waitForCount(1)
                // The second poll runs on an executor that records every enqueue. Its
                // first enqueue starts the task; a second one can only come from a
                // suspension inside `poll()` — the `Task.yield()` it spins on because
                // the first poll still holds the iterator. Waiting for it observes the
                // overlap before the gate opens, instead of assuming it from a delay
                // (#353).
                group.addTask(executorPreference: secondPollExecutor) { await dataSource.poll() }
                await secondPollExecutor.enqueues.waitForCount(2)
                firstLineGate.append(())

                var results: [MediaRemotePollResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            let titles = results.compactMap { result -> String? in
                guard case .info(let nowPlaying) = result else { return nil }
                return nowPlaying.title
            }
            #expect(Set(titles) == ["First", "Second"])
            #expect(gateway.runStreamingCallCount == 1)
            // One request per line, in order — and never two in flight at once: the
            // second poll's `next()` started only after the first's had returned.
            #expect(gateway.nextRequests.values == [0, 1])
            #expect(gateway.peakConcurrentNextRequests == 1)
        }
    }

    @Test("poll spawns the helper via the Apple-signed swift interpreter")
    func pollInvokesInterpretMode() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [frameLine(clients: [clientEntry()])]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl()
            _ = await dataSource.poll()

            #expect(gateway.streamingCommands.count == 1)
            let command = gateway.streamingCommands.first
            // Must be the absolute path to the Apple-signed swift interpreter —
            // using `/usr/bin/env swift` would respect $PATH and could resolve
            // to a non-Apple toolchain that loses the MediaRemote entitlement.
            #expect(command?.executable == "/usr/bin/swift")
            #expect(command?.arguments.count == 1)
            let scriptPath = command?.arguments.first ?? ""
            #expect(scriptPath.hasSuffix("media-remote-helper.swift"))
            // No compile step — the helper must NEVER be pre-built (see #261).
            #expect(gateway.runCommands.isEmpty)
        }
    }
}
