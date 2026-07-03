import Dependencies
import Domain
import Foundation
import Testing

@testable import MediaRemoteDataSource

@Suite("MediaRemoteDataSourceImpl")
struct MediaRemoteDataSourceImplTests {
    @Test("poll returns info for valid JSON line")
    func pollReturnsInfo() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [
                Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true)
            ]
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

    @Test("poll returns noInfo for has_info false payload")
    func pollReturnsNoInfo() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [
                Self.jsonLine(title: "Song", artist: "Artist", hasInfo: false)
            ]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl()
            let result = await dataSource.poll()
            guard case .noInfo = result else {
                Issue.record("Expected .noInfo, got \(result)")
                return
            }
        }
    }

    @Test("poll returns noInfo for invalid JSON")
    func pollReturnsNoInfoForInvalidJSON() async throws {
        let gateway = StreamingGateway(streamPlans: [
            ["{not-json}"]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl()
            let result = await dataSource.poll()
            guard case .noInfo = result else {
                Issue.record("Expected .noInfo, got \(result)")
                return
            }
        }
    }

    @Test("poll returns noInfo for empty line")
    func pollReturnsNoInfoForEmptyLine() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [""]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl()
            let result = await dataSource.poll()
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
            [Self.jsonLine(title: "Restarted", artist: "Artist", hasInfo: true)],
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
    func concurrentPollsSerializeIteratorAccess() async throws {
        let gateway = StreamingGateway(
            streamPlans: [
                [
                    Self.jsonLine(title: "First", artist: "Artist", hasInfo: true),
                    Self.jsonLine(title: "Second", artist: "Artist", hasInfo: true),
                ]
            ],
            firstYieldDelayNanoseconds: 50_000_000
        )

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl()
            let results = await withTaskGroup(of: MediaRemotePollResult.self) { group in
                group.addTask { await dataSource.poll() }
                group.addTask { await dataSource.poll() }

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
        }
    }

    @Test("artwork base64 is decoded once while the payload is unchanged")
    func artworkDecodedOnceForUnchangedBase64() async throws {
        let artwork = Data("artwork-bytes".utf8).base64EncodedString()
        let gateway = StreamingGateway(streamPlans: [
            [
                Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true, artworkBase64: artwork),
                Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true, artworkBase64: artwork),
            ]
        ])
        let decoder = CountingDecoder()

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(decodeBase64: decoder.decode)
            let artworks = [await dataSource.poll(), await dataSource.poll()].map {
                result -> Data? in
                guard case .info(let nowPlaying) = result else {
                    Issue.record("Expected .info, got \(result)")
                    return nil
                }
                return nowPlaying.artworkData
            }

            #expect(artworks == [Data("artwork-bytes".utf8), Data("artwork-bytes".utf8)])
            #expect(decoder.count == 1)
        }
    }

    @Test("artwork base64 is re-decoded when the payload changes")
    func artworkRedecodedForChangedBase64() async throws {
        let firstArtwork = Data("first-artwork".utf8).base64EncodedString()
        let secondArtwork = Data("second-artwork".utf8).base64EncodedString()
        let gateway = StreamingGateway(streamPlans: [
            [
                Self.jsonLine(
                    title: "Song", artist: "Artist", hasInfo: true, artworkBase64: firstArtwork),
                Self.jsonLine(
                    title: "Song", artist: "Artist", hasInfo: true, artworkBase64: secondArtwork),
            ]
        ])
        let decoder = CountingDecoder()

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(decodeBase64: decoder.decode)
            let artworks = [await dataSource.poll(), await dataSource.poll()].map {
                result -> Data? in
                guard case .info(let nowPlaying) = result else {
                    Issue.record("Expected .info, got \(result)")
                    return nil
                }
                return nowPlaying.artworkData
            }

            #expect(artworks == [Data("first-artwork".utf8), Data("second-artwork".utf8)])
            #expect(decoder.count == 2)
        }
    }

    @Test("artwork decode is skipped when the payload has no artwork")
    func artworkDecodeSkippedForMissingArtwork() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true)]
        ])
        let decoder = CountingDecoder()

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(decodeBase64: decoder.decode)
            let result = await dataSource.poll()

            guard case .info(let nowPlaying) = result else {
                Issue.record("Expected .info, got \(result)")
                return
            }
            #expect(nowPlaying.artworkData == nil)
            #expect(decoder.count == 0)
        }
    }

    @Test("tick payload without artwork reuses the last track-change cover (#255)")
    func tickReusesLastArtwork() async throws {
        let artwork = Data("cover".utf8).base64EncodedString()
        let gateway = StreamingGateway(streamPlans: [
            [
                Self.jsonLine(
                    title: "Song", artist: "Artist", hasInfo: true, artworkBase64: artwork,
                    event: "track-change"),
                Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true, event: "tick"),
            ]
        ])
        let decoder = CountingDecoder()

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(decodeBase64: decoder.decode)
            let artworks = [await dataSource.poll(), await dataSource.poll()].map {
                result -> Data? in
                guard case .info(let nowPlaying) = result else {
                    Issue.record("Expected .info, got \(result)")
                    return nil
                }
                return nowPlaying.artworkData
            }

            // The tick omits artwork, so the cached cover is reused — and decoded
            // only once.
            #expect(artworks == [Data("cover".utf8), Data("cover".utf8)])
            #expect(decoder.count == 1)
        }
    }

    @Test("track-change payload without artwork clears the cached cover (#255)")
    func trackChangeWithoutArtworkClearsCache() async throws {
        let artwork = Data("cover".utf8).base64EncodedString()
        let gateway = StreamingGateway(streamPlans: [
            [
                Self.jsonLine(
                    title: "First", artist: "Artist", hasInfo: true, artworkBase64: artwork,
                    event: "track-change"),
                Self.jsonLine(title: "Second", artist: "Artist", hasInfo: true, event: "track-change"),
                Self.jsonLine(title: "Second", artist: "Artist", hasInfo: true, event: "tick"),
            ]
        ])
        let decoder = CountingDecoder()

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(decodeBase64: decoder.decode)
            let artworks = [
                await dataSource.poll(), await dataSource.poll(), await dataSource.poll(),
            ].map { result -> Data? in
                guard case .info(let nowPlaying) = result else {
                    Issue.record("Expected .info, got \(result)")
                    return nil
                }
                return nowPlaying.artworkData
            }

            // The cover-less track-change drops the cache, and the following tick
            // has nothing to reuse.
            #expect(artworks == [Data("cover".utf8), nil, nil])
            #expect(decoder.count == 1)
        }
    }

    @Test("tick before any track-change yields no artwork (#255)")
    func tickBeforeAnyArtworkYieldsNil() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true, event: "tick")]
        ])
        let decoder = CountingDecoder()

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(decodeBase64: decoder.decode)
            let result = await dataSource.poll()

            guard case .info(let nowPlaying) = result else {
                Issue.record("Expected .info, got \(result)")
                return
            }
            #expect(nowPlaying.artworkData == nil)
            #expect(decoder.count == 0)
        }
    }

    @Test("pid from the helper payload is surfaced, absent pid yields nil (#23)")
    func pidIsDecoded() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [
                Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true, pid: 4242),
                Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true),
            ]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl()
            let pids = [await dataSource.poll(), await dataSource.poll()].map {
                result -> Int? in
                guard case .info(let nowPlaying) = result else {
                    Issue.record("Expected .info, got \(result)")
                    return nil
                }
                return nowPlaying.pid
            }

            #expect(pids == [4242, nil])
        }
    }

    @Test("poll spawns the helper via the Apple-signed swift interpreter")
    func pollInvokesInterpretMode() async throws {
        let gateway = StreamingGateway(streamPlans: [
            [Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true)]
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

extension MediaRemoteDataSourceImplTests {
    fileprivate static func jsonLine(
        title: String, artist: String, hasInfo: Bool, artworkBase64: String? = nil,
        event: String? = nil, pid: Int? = nil
    ) -> String {
        let payload: [String: Any] = [
            "has_info": hasInfo,
            "title": title,
            "artist": artist,
            "duration": 123.0,
            "elapsed": 4.5,
            "rate": 1.0,
            "timestamp": 10.0,
        ]
        .merging(artworkBase64.map { ["artwork_base64": $0] } ?? [:]) { _, new in new }
        .merging(event.map { ["event": $0] } ?? [:]) { _, new in new }
        .merging(pid.map { ["pid": $0] } ?? [:]) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

private final class CountingDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var decodeCallCount = 0

    var count: Int {
        lock.withLock { decodeCallCount }
    }

    @Sendable func decode(_ base64: String) -> Data? {
        lock.withLock {
            decodeCallCount += 1
            return Data(base64Encoded: base64)
        }
    }
}

private struct CapturedCommand: Sendable {
    let executable: String
    let arguments: [String]
}

private final class StreamingGateway: ProcessGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var streamPlans: [[String]]
    private let firstYieldDelayNanoseconds: UInt64
    private(set) var runStreamingCallCount = 0
    private var capturedRunCommands: [CapturedCommand] = []
    private var capturedStreamingCommands: [CapturedCommand] = []

    init(
        streamPlans: [[String]],
        firstYieldDelayNanoseconds: UInt64 = 0
    ) {
        self.streamPlans = streamPlans
        self.firstYieldDelayNanoseconds = firstYieldDelayNanoseconds
    }

    var runCommands: [CapturedCommand] {
        lock.withLock { capturedRunCommands }
    }

    var streamingCommands: [CapturedCommand] {
        lock.withLock { capturedStreamingCommands }
    }

    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { [] }
    func spawnDaemon(executablePath: String) -> Int32? { nil }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { false }
    func isRunning(_ pid: Int32) -> Bool { false }
    func acquireLock() -> Bool { false }
    var isLocked: Bool { false }
    func releaseLock() {}
    func runLaunchctl(_ arguments: [String]) -> Int32 { 0 }
    func findExecutable(_ name: String) -> String? { nil }
    func run(executable: String, arguments: [String]) -> Int32 {
        lock.withLock {
            capturedRunCommands.append(CapturedCommand(executable: executable, arguments: arguments))
            return 0
        }
    }
    func runInteractiveShell(_ command: String) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }

    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        let lines: [String] = lock.withLock {
            runStreamingCallCount += 1
            capturedStreamingCommands.append(
                CapturedCommand(executable: executable, arguments: arguments))
            guard !streamPlans.isEmpty else { return [] }
            return streamPlans.removeFirst()
        }

        return AsyncStream { continuation in
            let task = Task {
                for (index, line) in lines.enumerated() {
                    if index == 0, firstYieldDelayNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: firstYieldDelayNanoseconds)
                    }
                    continuation.yield(line)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
