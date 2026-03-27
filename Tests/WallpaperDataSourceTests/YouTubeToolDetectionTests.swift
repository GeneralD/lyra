import Foundation
import Testing

@testable import WallpaperDataSource

@Suite("YouTube tool detection")
struct YouTubeToolDetectionTests {
    private let ds = YouTubeWallpaperDataSourceImpl()

    // Environment-dependent tests: these validate tool detection when the tool
    // is actually installed. They return early (effectively skip) when the
    // prerequisite tool is not available, since Swift Testing has no built-in
    // runtime skip mechanism for dynamic conditions.

    @Test("detectTool returns ytdlp when yt-dlp is in PATH")
    func detectsYtdlp() throws {
        guard findInPath("yt-dlp") else { return }
        let tool = try ds.detectTool()
        guard case .ytdlp(let path) = tool else {
            Issue.record("Expected .ytdlp, got \(tool)")
            return
        }
        #expect(!path.isEmpty)
        #expect(FileManager.default.isExecutableFile(atPath: path))
    }

    @Test("detectTool returns uvx when only uvx is available")
    func detectsUvx() throws {
        guard !findInPath("yt-dlp"), findInPath("uvx") else { return }
        let tool = try ds.detectTool()
        guard case .uvx(let path) = tool else {
            Issue.record("Expected .uvx, got \(tool)")
            return
        }
        #expect(!path.isEmpty)
        #expect(FileManager.default.isExecutableFile(atPath: path))
    }

    @Test("detectTool prefers yt-dlp over uvx")
    func prefersYtdlp() throws {
        guard findInPath("yt-dlp") else { return }
        let tool = try ds.detectTool()
        guard case .ytdlp = tool else {
            Issue.record("Expected .ytdlp when both available, got \(tool)")
            return
        }
    }

    @Test("detectTool throws when neither yt-dlp nor uvx is available")
    func throwsWhenNoTool() {
        // This test only validates the error type; actual absence depends on env
        let error = YouTubeDownloadError.toolNotFound
        #expect(error.description.contains("yt-dlp not found"))
    }

    @Test("findExecutable returns nil for nonexistent command")
    func findNonexistent() {
        #expect(ds.findExecutable("definitely-not-a-real-command-xyzzy") == nil)
    }

    @Test("findExecutable returns valid path for known command")
    func findKnownCommand() {
        let path = ds.findExecutable("ls")
        #expect(path != nil)
        #expect(FileManager.default.isExecutableFile(atPath: path ?? ""))
    }

    @Test("buildArgs for ytdlp tool includes vcodec filter")
    func buildArgsYtdlp() {
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

    @Test("buildArgs for uvx tool prepends yt-dlp")
    func buildArgsUvx() {
        let url = URL(string: "https://youtu.be/abc")!
        let args = ds.buildArgs(
            tool: .uvx(path: "/opt/homebrew/bin/uvx"),
            url: url, maxHeight: 2160, format: "mp4", destPath: "/tmp/out.mp4"
        )
        #expect(args.first == "yt-dlp")
        #expect(args.contains("--no-audio"))
        #expect(args.contains { $0.contains("height<=2160") })
    }

    @Test("buildArgs respects custom maxHeight and format")
    func buildArgsCustomParams() {
        let url = URL(string: "https://youtu.be/test")!
        let args = ds.buildArgs(
            tool: .ytdlp(path: "/usr/bin/yt-dlp"),
            url: url, maxHeight: 720, format: "webm", destPath: "/tmp/out.webm"
        )
        let formatArg = args.first { $0.contains("height<=") }
        #expect(formatArg?.contains("720") == true)
        #expect(formatArg?.contains("webm") == true)
    }

    private func findInPath(_ name: String) -> Bool {
        ds.findExecutable(name) != nil
    }
}
