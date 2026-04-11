import Dependencies
import Domain
import Foundation
import Testing

@testable import WallpaperDataSource

private struct LiveGateway: ProcessGateway {
    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { [] }
    func spawnDaemon(executablePath: String) -> Int32? { nil }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { false }
    func isRunning(_ pid: Int32) -> Bool { false }
    func acquireLock() -> Bool { false }
    var isLocked: Bool { false }
    func releaseLock() {}
    func runLaunchctl(_ arguments: [String]) -> Int32 { 0 }

    func findExecutable(_ name: String) -> String? {
        let known = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)", "/bin/\(name)"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        if let known { return known }

        guard let output = runCapturingOutput(executable: "/usr/bin/which", arguments: [name]),
            !output.isEmpty
        else { return nil }
        let resolved = URL(fileURLWithPath: output).standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: resolved) else { return nil }
        return resolved
    }

    func run(executable: String, arguments: [String]) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}

@Suite("YouTube tool detection")
struct YouTubeToolDetectionTests {

    @Test("detectTool returns ytdlp when yt-dlp is in PATH")
    func detectsYtdlp() throws {
        try withDependencies {
            $0.processGateway = LiveGateway()
        } operation: {
            let ds = YouTubeWallpaperDataSourceImpl()
            guard ds.findExecutable("yt-dlp") != nil else { return }
            let tool = try ds.detectTool()
            guard case .ytdlp(let path) = tool else {
                Issue.record("Expected .ytdlp, got \(tool)")
                return
            }
            #expect(!path.isEmpty)
        }
    }

    @Test("detectTool returns uvx when only uvx is available")
    func detectsUvx() throws {
        try withDependencies {
            $0.processGateway = LiveGateway()
        } operation: {
            let ds = YouTubeWallpaperDataSourceImpl()
            guard ds.findExecutable("yt-dlp") == nil, ds.findExecutable("uvx") != nil else { return }
            let tool = try ds.detectTool()
            guard case .uvx(let path) = tool else {
                Issue.record("Expected .uvx, got \(tool)")
                return
            }
            #expect(!path.isEmpty)
        }
    }

    @Test("detectTool prefers yt-dlp over uvx")
    func prefersYtdlp() throws {
        try withDependencies {
            $0.processGateway = LiveGateway()
        } operation: {
            let ds = YouTubeWallpaperDataSourceImpl()
            guard ds.findExecutable("yt-dlp") != nil else { return }
            let tool = try ds.detectTool()
            guard case .ytdlp = tool else {
                Issue.record("Expected .ytdlp when both available, got \(tool)")
                return
            }
        }
    }

    @Test("detectTool throws when neither yt-dlp nor uvx is available")
    func throwsWhenNoTool() {
        let error = YouTubeDownloadError.toolNotFound
        #expect(error.description.contains("yt-dlp not found"))
    }

    @Test("findExecutable returns nil for nonexistent command")
    func findNonexistent() {
        withDependencies {
            $0.processGateway = LiveGateway()
        } operation: {
            let ds = YouTubeWallpaperDataSourceImpl()
            #expect(ds.findExecutable("definitely-not-a-real-command-xyzzy") == nil)
        }
    }

    @Test("findExecutable returns valid path for known command")
    func findKnownCommand() {
        withDependencies {
            $0.processGateway = LiveGateway()
        } operation: {
            let ds = YouTubeWallpaperDataSourceImpl()
            let path = ds.findExecutable("ls")
            #expect(path != nil)
            #expect(FileManager.default.isExecutableFile(atPath: path ?? ""))
        }
    }

    @Test("buildArgs for ytdlp tool includes vcodec filter")
    func buildArgsYtdlp() {
        withDependencies {
            $0.processGateway = LiveGateway()
        } operation: {
            let ds = YouTubeWallpaperDataSourceImpl()
            let url = URL(string: "https://www.youtube.com/watch?v=test123")!
            let args = ds.buildArgs(
                tool: .ytdlp(path: "/usr/local/bin/yt-dlp"),
                url: url, maxHeight: 1080, format: "mp4", destPath: "/tmp/out.mp4"
            )
            #expect(args.contains("-f"))
            #expect(args.contains("--no-audio"))
            #expect(args.contains("/tmp/out.mp4"))
            #expect(args.contains(url.absoluteString))
            #expect(args.first { $0.contains("vcodec^=avc") } != nil)
        }
    }

    @Test("buildArgs for uvx tool prepends yt-dlp")
    func buildArgsUvx() {
        withDependencies {
            $0.processGateway = LiveGateway()
        } operation: {
            let ds = YouTubeWallpaperDataSourceImpl()
            let url = URL(string: "https://youtu.be/abc")!
            let args = ds.buildArgs(
                tool: .uvx(path: "/opt/homebrew/bin/uvx"),
                url: url, maxHeight: 2160, format: "mp4", destPath: "/tmp/out.mp4"
            )
            #expect(args.first == "yt-dlp")
        }
    }

    @Test("buildArgs respects custom maxHeight and format")
    func buildArgsCustomParams() {
        withDependencies {
            $0.processGateway = LiveGateway()
        } operation: {
            let ds = YouTubeWallpaperDataSourceImpl()
            let url = URL(string: "https://youtu.be/test")!
            let args = ds.buildArgs(
                tool: .ytdlp(path: "/usr/bin/yt-dlp"),
                url: url, maxHeight: 720, format: "webm", destPath: "/tmp/out.webm"
            )
            let formatArg = args.first { $0.contains("height<=") }
            #expect(formatArg?.contains("720") == true)
            #expect(formatArg?.contains("webm") == true)
        }
    }
}
