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
        let runner = ProcessRunner(results: [(1, "", "download failed")])
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
        let runner = ProcessRunner(results: [(0, "", "")])
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
        let runner = ProcessRunner(results: [(0, "", "")])
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
        // Without a transcode toolchain the AVC ceiling selector is used (natively playable).
        #expect(calls[0].arguments.contains { $0.contains("vcodec^=avc") })
        #expect(calls[0].arguments.contains("youtube:player_client=default"))
    }

    @Test("resolve uses uvx fallback when yt-dlp is missing")
    func resolveUsesUvx() async throws {
        let runner = ProcessRunner(results: [(0, "", "")])
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

    @Test("resolve throws remuxFailed when ffmpeg copy step exits non-zero")
    func resolveRemuxFailed() async {
        // ffmpeg present but ffprobe absent → no transcode capability → AVC selector + stream-copy.
        let runner = ProcessRunner(results: [(0, "", ""), (1, "", "remux failed")])
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
        #expect(calls[1].arguments.contains("copy"))
    }

    @Test("resolve transcodes AV1 to HEVC when ffmpeg and ffprobe are available")
    func resolveTranscodesAV1() async throws {
        // download → ffprobe (reports av1) → ffmpeg HEVC transcode
        let runner = ProcessRunner(results: [(0, "", ""), (0, "av1", ""), (0, "", "")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: [
                "yt-dlp": "/usr/bin/yt-dlp", "ffmpeg": "/usr/bin/ffmpeg", "ffprobe": "/usr/bin/ffprobe",
            ]),
            runner: runner,
            fileExists: true
        )

        let result = try await dataSource.resolve(location)
        let calls = await runner.calls

        #expect(result == tempPath)
        #expect(calls.count == 3)
        // Download requests the highest-quality (codec-agnostic) selector — no AVC restriction.
        #expect(!calls[0].arguments.contains { $0.contains("vcodec^=avc") })
        // Codec probe.
        #expect(calls[1].executablePath == "/usr/bin/ffprobe")
        #expect(calls[1].arguments.contains("stream=codec_name"))
        // HEVC hardware transcode.
        #expect(calls[2].executablePath == "/usr/bin/ffmpeg")
        #expect(calls[2].arguments.contains("hevc_videotoolbox"))
        #expect(calls[2].arguments.contains("hvc1"))
    }

    @Test("resolve stream-copies AVC/HEVC instead of transcoding")
    func resolveCopiesH264() async throws {
        let runner = ProcessRunner(results: [(0, "", ""), (0, "h264", ""), (0, "", "")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: [
                "yt-dlp": "/usr/bin/yt-dlp", "ffmpeg": "/usr/bin/ffmpeg", "ffprobe": "/usr/bin/ffprobe",
            ]),
            runner: runner,
            fileExists: true
        )

        _ = try await dataSource.resolve(location)
        let calls = await runner.calls

        #expect(calls.count == 3)
        #expect(calls[2].executablePath == "/usr/bin/ffmpeg")
        #expect(calls[2].arguments.contains("copy"))
        #expect(!calls[2].arguments.contains("hevc_videotoolbox"))
    }

    @Test("resolve throws transcodeFailed when the HEVC step exits non-zero")
    func resolveTranscodeFailed() async {
        let runner = ProcessRunner(results: [(0, "", ""), (0, "vp9", ""), (1, "", "gpu busy")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: [
                "yt-dlp": "/usr/bin/yt-dlp", "ffmpeg": "/usr/bin/ffmpeg", "ffprobe": "/usr/bin/ffprobe",
            ]),
            runner: runner,
            fileExists: true
        )

        do {
            _ = try await dataSource.resolve(location)
            Issue.record("Expected transcodeFailed")
        } catch let error as YouTubeDownloadError {
            guard case .transcodeFailed(let stderr) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(stderr == "gpu busy")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("resolve transcodes when ffprobe was expected but codec detection fails")
    func resolveTranscodesOnProbeFailure() async throws {
        // download → ffprobe FAILS (non-zero) → must still HEVC-transcode, never stream-copy:
        // the codec-agnostic download path may have produced an AV1/VP9 file that a copy would
        // leave unplayable on pre-M3 / Intel Macs.
        let runner = ProcessRunner(results: [(0, "", ""), (1, "", "probe error"), (0, "", "")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: [
                "yt-dlp": "/usr/bin/yt-dlp", "ffmpeg": "/usr/bin/ffmpeg", "ffprobe": "/usr/bin/ffprobe",
            ]),
            runner: runner,
            fileExists: true
        )

        _ = try await dataSource.resolve(location)
        let calls = await runner.calls

        #expect(calls.count == 3)
        #expect(calls[2].executablePath == "/usr/bin/ffmpeg")
        #expect(calls[2].arguments.contains("hevc_videotoolbox"))
        #expect(!calls[2].arguments.contains("copy"))
    }

    @Test("public init helper closures execute successfully")
    func publicInitHelpers() async throws {
        // The live processRunner closure now delegates to a ProcessExecutor captured at
        // init (#340), so construct the DataSource inside the override to prove the no-arg
        // init wired the closure — without spawning a real subprocess.
        let dataSource = withDependencies {
            $0.processExecutor = StubProcessExecutor(result: (status: 0, stdout: "", stderr: ""))
        } operation: {
            YouTubeWallpaperDataSourceImpl()
        }
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

    // The real-subprocess coverage (status/stdout/stderr capture, launch failure) that
    // used to exercise YouTube's own `executeProcess` static now lives on the shared
    // primitive `DarwinGateway.runProcess` (#340); the resolve tests below still stub the
    // `processRunner` seam, so they are unaffected by the consolidation.

    @Test("error descriptions include contextual details")
    func errorDescriptions() {
        #expect(YouTubeDownloadError.toolNotFound.description.contains("brew install yt-dlp"))
        #expect(YouTubeDownloadError.downloadFailed(status: 7, stderr: "boom").description == "yt-dlp exited with status 7\nboom")
        #expect(YouTubeDownloadError.outputNotFound.description == "yt-dlp completed but output file not found")
        #expect(YouTubeDownloadError.remuxFailed(stderr: "bad mux").description == "ffmpeg remux failed\nbad mux")
        #expect(YouTubeDownloadError.transcodeFailed(stderr: "no gpu").description == "ffmpeg HEVC transcode failed\nno gpu")
    }
}

@Suite("YouTubeWallpaperDataSourceImpl format selection and normalization")
struct YouTubeWallpaperFormatTests {
    private let dataSource = YouTubeWallpaperDataSourceImpl()

    @Test("format selector keeps the AVC ceiling when transcoding is unavailable")
    func selectorAVCWhenNoTranscode() {
        let selector = dataSource.formatSelector(maxHeight: 2160, format: "mp4", allowAnyCodec: false)
        #expect(selector.contains("vcodec^=avc"))
        #expect(selector.contains("ext=mp4"))
        #expect(selector.contains("height<=2160"))
    }

    @Test("format selector drops codec restrictions when transcoding is available")
    func selectorAnyCodecWhenTranscode() {
        let selector = dataSource.formatSelector(maxHeight: 2160, format: "mp4", allowAnyCodec: true)
        #expect(!selector.contains("vcodec"))
        #expect(!selector.contains("ext="))
        #expect(selector.contains("bestvideo[height<=2160]"))
    }

    @Test("requiresTranscode flags only AV1 and VP9 families")
    func requiresTranscodeMatrix() {
        #expect(YouTubeWallpaperDataSourceImpl.requiresTranscode("av1"))
        #expect(YouTubeWallpaperDataSourceImpl.requiresTranscode("av01"))
        #expect(YouTubeWallpaperDataSourceImpl.requiresTranscode("vp9"))
        #expect(YouTubeWallpaperDataSourceImpl.requiresTranscode("vp09"))
        #expect(!YouTubeWallpaperDataSourceImpl.requiresTranscode("h264"))
        #expect(!YouTubeWallpaperDataSourceImpl.requiresTranscode("hevc"))
    }

    @Test("ffmpeg argument builders produce playback-ready MP4 commands")
    func ffmpegArgumentBuilders() {
        let remux = YouTubeWallpaperDataSourceImpl.remuxArguments(input: "/in.mp4", output: "/out.mp4")
        #expect(remux.first == "-nostdin")
        #expect(remux.contains("copy"))
        #expect(remux.contains("+faststart"))
        #expect(remux.last == "/out.mp4")

        let transcode = YouTubeWallpaperDataSourceImpl.transcodeArguments(input: "/in.mp4", output: "/out.mp4")
        #expect(transcode.contains("hevc_videotoolbox"))
        #expect(transcode.contains("hvc1"))
        #expect(transcode.contains("-an"))
        #expect(transcode.contains("+faststart"))
        #expect(transcode.last == "/out.mp4")
    }

    @Test("videoCodec returns nil when ffprobe is unavailable")
    func videoCodecNilWithoutFfprobe() async {
        let codec = await dataSource.videoCodec(at: "/tmp/whatever.mp4", ffprobe: nil)
        #expect(codec == nil)
    }

    @Test("needsTranscode is false without ffprobe (AVC-only download is always playable)")
    func needsTranscodeFalseWithoutFfprobe() async {
        let needs = await dataSource.needsTranscode(at: "/tmp/whatever.mp4", ffprobe: nil)
        #expect(needs == false)
    }

    @Test("needsTranscode is true when ffprobe was expected but the probe fails")
    func needsTranscodeTrueOnProbeFailure() async {
        // A probe failure in the codec-agnostic download path cannot rule out AV1/VP9, so the
        // file must be transcoded rather than risk an unplayable stream copy.
        let runner = ProcessRunner(results: [(1, "", "probe error")])
        let dataSource = makeDataSource(
            gateway: StubGateway(executables: ["ffprobe": "/usr/bin/ffprobe"]),
            runner: runner,
            fileExists: true
        )
        let needs = await dataSource.needsTranscode(at: "/tmp/whatever.mp4", ffprobe: "/usr/bin/ffprobe")
        #expect(needs == true)
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
    func runProcess(executable: String, arguments: [String], environment: [String: String]) async throws -> (
        status: Int32, stdout: String, stderr: String
    ) { fatalError("unused") }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in continuation.finish() }
    }
}

private struct StubProcessExecutor: ProcessExecutor {
    let result: (status: Int32, stdout: String, stderr: String)
    func run(
        executable: String, arguments: [String], environment: [String: String], timeoutMs: Double?
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        result
    }
}

private actor ProcessRunner {
    typealias ResultTuple = (status: Int32, stdout: String, stderr: String)

    private(set) var calls: [(executablePath: String, arguments: [String])] = []
    private var results: [ResultTuple]

    init(results: [ResultTuple]) {
        self.results = results
    }

    func run(executablePath: String, arguments: [String]) -> ResultTuple {
        calls.append((executablePath, arguments))
        guard !results.isEmpty else {
            Issue.record("ProcessRunner.run called more times than stubbed results for \(executablePath) \(arguments)")
            return (status: 1, stdout: "", stderr: "No stubbed process result available.")
        }
        return results.removeFirst()
    }
}
