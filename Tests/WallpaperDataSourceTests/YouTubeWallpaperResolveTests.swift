import Dependencies
import Domain
import Foundation
import Testing

@testable import WallpaperDataSource

@Suite("YouTubeWallpaperDataSourceImpl resolve", .serialized)
struct YouTubeWallpaperResolveTests {
    private let location = YouTubeWallpaper(url: URL(string: "https://youtu.be/demo")!, maxHeight: 1080, format: "mp4")
    private let tempPath = "/tmp/lyra-youtube-test.mp4"

    @Test("resolve throws toolNotFound when no downloader exists")
    func resolveToolMissing() async {
        let dataSource = makeDataSource(gateway: StubGateway(executables: [:]), runner: ProcessRunner(results: []), fileExists: false)

        do {
            _ = try await dataSource.resolve(location)
            Issue.record("Expected toolNotFound")
        } catch let error as YouTubeDownloadError {
            guard case .toolNotFound = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("resolve throws downloadFailed when downloader exits non-zero")
    func resolveDownloadFailed() async {
        let runner = ProcessRunner(results: [(1, "download failed")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: ["yt-dlp": "/usr/bin/yt-dlp"]),
            runner: runner,
            fileExists: false
        )

        do {
            _ = try await dataSource.resolve(location)
            Issue.record("Expected download failure")
        } catch let error as YouTubeDownloadError {
            guard case .downloadFailed(let status, let stderr) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(status == 1)
            #expect(stderr == "download failed")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("resolve throws outputNotFound when downloader succeeds without file")
    func resolveOutputMissing() async {
        let runner = ProcessRunner(results: [(0, "")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: ["yt-dlp": "/usr/bin/yt-dlp"]),
            runner: runner,
            fileExists: false
        )

        do {
            _ = try await dataSource.resolve(location)
            Issue.record("Expected outputNotFound")
        } catch let error as YouTubeDownloadError {
            guard case .outputNotFound = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("resolve returns temp path when download succeeds and ffmpeg is unavailable")
    func resolveSuccessWithoutRemux() async throws {
        let runner = ProcessRunner(results: [(0, "")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: ["yt-dlp": "/usr/bin/yt-dlp"]),
            runner: runner,
            fileExists: true
        )

        let result = try await dataSource.resolve(location)

        let calls = await runner.calls
        #expect(result == tempPath)
        #expect(calls.count == 1)
        #expect(calls[0].executablePath == "/usr/bin/yt-dlp")
        #expect(calls[0].arguments.contains(location.url.absoluteString))
    }

    @Test("resolve uses uvx fallback when yt-dlp is missing")
    func resolveUsesUvx() async throws {
        let runner = ProcessRunner(results: [(0, "")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: ["uvx": "/usr/bin/uvx"]),
            runner: runner,
            fileExists: true
        )

        _ = try await dataSource.resolve(location)

        let calls = await runner.calls
        #expect(calls.count == 1)
        #expect(calls[0].executablePath == "/usr/bin/uvx")
        #expect(calls[0].arguments.first == "yt-dlp")
    }

    @Test("resolve throws remuxFailed when ffmpeg step exits non-zero")
    func resolveRemuxFailed() async {
        let runner = ProcessRunner(results: [(0, ""), (1, "remux failed")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: ["yt-dlp": "/usr/bin/yt-dlp", "ffmpeg": "/usr/bin/ffmpeg"]),
            runner: runner,
            fileExists: true
        )

        do {
            _ = try await dataSource.resolve(location)
            Issue.record("Expected remuxFailed")
        } catch let error as YouTubeDownloadError {
            guard case .remuxFailed(let stderr) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(stderr == "remux failed")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let calls = await runner.calls
        #expect(calls.count == 2)
        #expect(calls[1].executablePath == "/usr/bin/ffmpeg")
        #expect(calls[1].arguments.first == "-nostdin")
    }

    @Test("public init helper closures execute successfully")
    func publicInitHelpers() async throws {
        let dataSource = YouTubeWallpaperDataSourceImpl()
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let cachedPath = try dataSource.tempPathFor(location.url, location.format)
        let runResult = try await dataSource.processRunner("/bin/sh", ["-c", "exit 0"])
        let existingPath = tempDir.appendingPathComponent("existing.txt").path
        try Data("x".utf8).write(to: URL(fileURLWithPath: existingPath))
        let removablePath = tempDir.appendingPathComponent("remove.txt").path
        try Data("y".utf8).write(to: URL(fileURLWithPath: removablePath))
        let originalPath = tempDir.appendingPathComponent("original.txt").path
        let replacementPath = tempDir.appendingPathComponent("replacement.txt").path
        try Data("old".utf8).write(to: URL(fileURLWithPath: originalPath))
        try Data("new".utf8).write(to: URL(fileURLWithPath: replacementPath))

        #expect(cachedPath.hasSuffix(".mp4"))
        #expect(runResult.status == 0)
        #expect(dataSource.fileExistsAtPath(existingPath))

        dataSource.removeItemAtPath(removablePath)
        #expect(!fm.fileExists(atPath: removablePath))

        dataSource.replaceItemAtPath(originalPath, replacementPath)
        #expect(fm.fileExists(atPath: originalPath))
    }

    @Test("executeProcess returns status and captured stderr")
    func executeProcessCapturesStderr() async throws {
        let result = try await YouTubeWallpaperDataSourceImpl.executeProcess(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo boom 1>&2; exit 7"]
        )

        #expect(result.status == 7)
        #expect(result.stderr == "boom")
    }

    @Test("executeProcess throws when executable cannot be launched")
    func executeProcessThrows() async {
        await #expect(throws: (any Error).self) {
            _ = try await YouTubeWallpaperDataSourceImpl.executeProcess(
                executablePath: "/definitely/missing/executable",
                arguments: []
            )
        }
    }

    @Test("error descriptions include contextual details")
    func errorDescriptions() {
        #expect(YouTubeDownloadError.toolNotFound.description.contains("brew install yt-dlp"))
        #expect(YouTubeDownloadError.downloadFailed(status: 7, stderr: "boom").description == "yt-dlp exited with status 7\nboom")
        #expect(YouTubeDownloadError.outputNotFound.description == "yt-dlp completed but output file not found")
        #expect(YouTubeDownloadError.remuxFailed(stderr: "bad mux").description == "ffmpeg remux failed\nbad mux")
    }
}

private func makeDataSource(
    gateway: StubGateway,
    runner: ProcessRunner,
    fileExists: Bool
) -> YouTubeWallpaperDataSourceImpl {
    withDependencies {
        $0.processGateway = gateway
    } operation: {
        YouTubeWallpaperDataSourceImpl(
            tempPathFor: { _, _ in "/tmp/lyra-youtube-test.mp4" },
            processRunner: { executablePath, arguments in
                await runner.run(executablePath: executablePath, arguments: arguments)
            },
            fileExistsAtPath: { _ in fileExists },
            removeItemAtPath: { _ in },
            replaceItemAtPath: { _, _ in }
        )
    }
}

private struct StubGateway: ProcessGateway {
    let executables: [String: String]

    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { [] }
    func spawnDaemon(executablePath: String) -> Int32? { nil }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { false }
    func isRunning(_ pid: Int32) -> Bool { false }
    func acquireLock() -> Bool { false }
    var isLocked: Bool { false }
    func releaseLock() {}
    func runLaunchctl(_ arguments: [String]) -> Int32 { 0 }
    func findExecutable(_ name: String) -> String? { executables[name] }
    func run(executable: String, arguments: [String]) -> Int32 { 0 }
    func runInteractiveShell(_ command: String) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in continuation.finish() }
    }
}

private actor ProcessRunner {
    typealias ResultTuple = (status: Int32, stderr: String)

    private(set) var calls: [(executablePath: String, arguments: [String])] = []
    private var results: [ResultTuple]

    init(results: [ResultTuple]) {
        self.results = results
    }

    func run(executablePath: String, arguments: [String]) -> ResultTuple {
        calls.append((executablePath, arguments))
        guard !results.isEmpty else {
            Issue.record("ProcessRunner.run called more times than stubbed results for \(executablePath) \(arguments)")
            return (status: 1, stderr: "No stubbed process result available.")
        }
        return results.removeFirst()
    }
}
