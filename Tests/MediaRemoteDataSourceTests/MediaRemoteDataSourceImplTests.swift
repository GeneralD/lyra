import Dependencies
import Domain
import Foundation
import Testing

@testable import MediaRemoteDataSource

@Suite("MediaRemoteDataSourceImpl")
struct MediaRemoteDataSourceImplTests {
    @Test("poll returns info for valid JSON line")
    func pollReturnsInfo() async throws {
        let cacheHome = try Self.makeTemporaryCacheHome()
        defer { Self.cleanUp(cacheHome) }
        let gateway = StreamingGateway(streamPlans: [
            [
                Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true)
            ]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(cacheHome: cacheHome)
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
        let cacheHome = try Self.makeTemporaryCacheHome()
        defer { Self.cleanUp(cacheHome) }
        let gateway = StreamingGateway(streamPlans: [
            [
                Self.jsonLine(title: "Song", artist: "Artist", hasInfo: false)
            ]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(cacheHome: cacheHome)
            let result = await dataSource.poll()
            guard case .noInfo = result else {
                Issue.record("Expected .noInfo, got \(result)")
                return
            }
        }
    }

    @Test("poll returns noInfo for invalid JSON")
    func pollReturnsNoInfoForInvalidJSON() async throws {
        let cacheHome = try Self.makeTemporaryCacheHome()
        defer { Self.cleanUp(cacheHome) }
        let gateway = StreamingGateway(streamPlans: [
            ["{not-json}"]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(cacheHome: cacheHome)
            let result = await dataSource.poll()
            guard case .noInfo = result else {
                Issue.record("Expected .noInfo, got \(result)")
                return
            }
        }
    }

    @Test("poll returns noInfo for empty line")
    func pollReturnsNoInfoForEmptyLine() async throws {
        let cacheHome = try Self.makeTemporaryCacheHome()
        defer { Self.cleanUp(cacheHome) }
        let gateway = StreamingGateway(streamPlans: [
            [""]
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(cacheHome: cacheHome)
            let result = await dataSource.poll()
            guard case .noInfo = result else {
                Issue.record("Expected .noInfo, got \(result)")
                return
            }
        }
    }

    @Test("poll restarts stream after eof")
    func pollRestartsAfterEof() async throws {
        let cacheHome = try Self.makeTemporaryCacheHome()
        defer { Self.cleanUp(cacheHome) }
        let gateway = StreamingGateway(streamPlans: [
            [],
            [Self.jsonLine(title: "Restarted", artist: "Artist", hasInfo: true)],
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(cacheHome: cacheHome)
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
        let cacheHome = try Self.makeTemporaryCacheHome()
        defer { Self.cleanUp(cacheHome) }
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
            let dataSource = MediaRemoteDataSourceImpl(cacheHome: cacheHome)
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

    @Test("poll compiles helper once and streams the resulting binary")
    func pollCompilesHelperBinary() async throws {
        let cacheHome = try Self.makeTemporaryCacheHome()
        defer { Self.cleanUp(cacheHome) }
        let gateway = StreamingGateway(streamPlans: [
            [Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true)],
            [Self.jsonLine(title: "Song", artist: "Artist", hasInfo: true)],
        ])

        await withDependencies {
            $0.processGateway = gateway
        } operation: {
            let dataSource = MediaRemoteDataSourceImpl(cacheHome: cacheHome)
            _ = await dataSource.poll()
            _ = await dataSource.poll()

            #expect(gateway.runCommands.count == 1)
            let buildCommand = gateway.runCommands.first
            #expect(buildCommand?.executable == "/usr/bin/env")
            #expect(buildCommand?.arguments.first == "swiftc")
            #expect(buildCommand?.arguments.contains("-O") == true)

            let executablePaths = Set(gateway.streamingCommands.map(\.executable))
            #expect(executablePaths.count == 1)
            guard let binaryPath = executablePaths.first else {
                Issue.record("Expected streamingCommands to capture an executable path")
                return
            }
            #expect(binaryPath.hasSuffix("/lyra/media-remote-helper"))
            #expect(binaryPath.hasPrefix(cacheHome))
            #expect(gateway.streamingCommands.allSatisfy { $0.arguments.isEmpty })

            let shaPath = "\(cacheHome)/lyra/media-remote-helper.swift.sha"
            #expect(FileManager.default.fileExists(atPath: shaPath))
        }
    }
}

extension MediaRemoteDataSourceImplTests {
    fileprivate static func jsonLine(title: String, artist: String, hasInfo: Bool) -> String {
        let payload: [String: Any] = [
            "has_info": hasInfo,
            "title": title,
            "artist": artist,
            "duration": 123.0,
            "elapsed": 4.5,
            "rate": 1.0,
            "timestamp": 10.0,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    fileprivate static func makeTemporaryCacheHome() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "lyra-media-remote-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    fileprivate static func cleanUp(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
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

    init(streamPlans: [[String]], firstYieldDelayNanoseconds: UInt64 = 0) {
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
        }
        return 0
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
