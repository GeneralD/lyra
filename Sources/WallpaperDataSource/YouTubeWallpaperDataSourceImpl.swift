import Dependencies
import Domain
import Foundation

public struct YouTubeWallpaperDataSourceImpl: Sendable {
    @Dependency(\.processGateway) private var gateway
    let tempPathFor: @Sendable (URL, String?) throws -> String
    let processRunner: @Sendable (String, [String]) async throws -> (status: Int32, stdout: String, stderr: String)
    let fileExistsAtPath: @Sendable (String) -> Bool
    let removeItemAtPath: @Sendable (String) -> Void
    let replaceItemAtPath: @Sendable (String, String) -> Void

    public init() {
        // Resolve+capture the executor from the init-time context (the daemon's live DI
        // graph), so a construction-time override sticks in tests.
        @Dependency(\.processExecutor) var processExecutor
        self.init(
            tempPathFor: { url, ext in
                try WallpaperCache().tempPath(for: url, ext: ext)
            },
            processRunner: { executablePath, arguments in
                // timeout nil: yt-dlp/ffmpeg are long-lived and must run to completion.
                // Pass the daemon's inherited environment (as the old executeProcess did by
                // never setting process.environment) so the tools keep their PATH etc.
                try await processExecutor.run(
                    executable: executablePath, arguments: arguments,
                    environment: ProcessInfo.processInfo.environment, timeoutMs: nil)
            },
            fileExistsAtPath: { path in
                FileManager.default.fileExists(atPath: path)
            },
            removeItemAtPath: { path in
                try? FileManager.default.removeItem(atPath: path)
            },
            replaceItemAtPath: { originalPath, replacementPath in
                _ = try? FileManager.default.replaceItemAt(
                    URL(fileURLWithPath: originalPath),
                    withItemAt: URL(fileURLWithPath: replacementPath)
                )
            }
        )
    }

    init(
        tempPathFor: @escaping @Sendable (URL, String?) throws -> String,
        processRunner: @escaping @Sendable (String, [String]) async throws -> (status: Int32, stdout: String, stderr: String),
        fileExistsAtPath: @escaping @Sendable (String) -> Bool,
        removeItemAtPath: @escaping @Sendable (String) -> Void,
        replaceItemAtPath: @escaping @Sendable (String, String) -> Void
    ) {
        self.tempPathFor = tempPathFor
        self.processRunner = processRunner
        self.fileExistsAtPath = fileExistsAtPath
        self.removeItemAtPath = removeItemAtPath
        self.replaceItemAtPath = replaceItemAtPath
    }
}

extension YouTubeWallpaperDataSourceImpl: WallpaperDataSource {
    /// Downloads and normalizes to a temp file in the cache folder. Returns the temp file path.
    /// Cache deduplication is handled by WallpaperRepository.
    public func resolve(_ location: YouTubeWallpaper) async throws -> String {
        let tempPath = try tempPathFor(location.url, location.format)

        // Highest-quality codecs (VP9 / AV1 4K) are not natively playable by AVFoundation on
        // pre-M3 Apple Silicon and Intel Macs, so we only request them when we can transcode the
        // result to HEVC. Without a transcode toolchain we stay on the natively-playable AVC ceiling.
        let ffmpeg = findExecutable("ffmpeg")
        let ffprobe = findExecutable("ffprobe")
        let canTranscode = ffmpeg != nil && ffprobe != nil

        let tool = try detectTool()
        let args = buildArgs(
            tool: tool, url: location.url, maxHeight: location.maxHeight,
            format: location.format, destPath: tempPath, allowAnyCodec: canTranscode)

        let (status, _, stderr) = try await processRunner(tool.executablePath, args)

        guard status == 0 else {
            throw YouTubeDownloadError.downloadFailed(status: status, stderr: stderr)
        }

        guard fileExistsAtPath(tempPath) else {
            throw YouTubeDownloadError.outputNotFound
        }

        try await normalizeForPlayback(at: tempPath, ffmpeg: ffmpeg, ffprobe: ffprobe)

        return tempPath
    }
}

// MARK: - Tool Detection

extension YouTubeWallpaperDataSourceImpl {
    enum Tool {
        case ytdlp(path: String)
        case uvx(path: String)

        var executablePath: String {
            switch self {
            case .ytdlp(let path): path
            case .uvx(let path): path
            }
        }
    }

    func detectTool() throws -> Tool {
        if let path = findExecutable("yt-dlp") {
            return .ytdlp(path: path)
        }
        if let path = findExecutable("uvx") {
            return .uvx(path: path)
        }
        throw YouTubeDownloadError.toolNotFound
    }

    func findExecutable(_ name: String) -> String? {
        gateway.findExecutable(name)
    }
}

// MARK: - Command Building

extension YouTubeWallpaperDataSourceImpl {
    func buildArgs(
        tool: Tool, url: URL, maxHeight: Int, format: String, destPath: String, allowAnyCodec: Bool
    ) -> [String] {
        let ytdlpArgs =
            [
                // The Android player client is now crippled by YouTube SABR streaming, which skips
                // every video-only format and leaves only the combined 360p (format 18) — the
                // "sometimes terrible quality" bug. The default web client publishes the full
                // https DASH ladder (all resolutions, all codecs) with no PO Token required, so it
                // is the client that can actually reach 4K. --no-audio keeps this to a video-only
                // download (audio is never needed for a wallpaper).
                "--extractor-args", "youtube:player_client=default",
                "-f", formatSelector(maxHeight: maxHeight, format: format, allowAnyCodec: allowAnyCodec),
                "--no-audio",
                "--no-progress",
                "-o", destPath,
                url.absoluteString,
            ]
        switch tool {
        case .ytdlp: return ytdlpArgs
        case .uvx: return ["yt-dlp"] + ytdlpArgs
        }
    }

    /// When `allowAnyCodec` is true, take the highest-resolution video-only stream regardless of
    /// codec (VP9 / AV1 reach 4K; the result is transcoded to HEVC downstream). Otherwise restrict
    /// to AVC, which AVFoundation plays natively but YouTube caps at 1080p.
    func formatSelector(maxHeight: Int, format: String, allowAnyCodec: Bool) -> String {
        guard allowAnyCodec else {
            return "bestvideo[ext=\(format)][height<=\(maxHeight)][vcodec^=avc]/best[ext=\(format)][height<=\(maxHeight)]"
        }
        return "bestvideo[height<=\(maxHeight)]/best[height<=\(maxHeight)]"
    }
}

// MARK: - Playback Normalization

extension YouTubeWallpaperDataSourceImpl {
    /// Rewrites the downloaded file into an AVFoundation-playable MP4: AVC/HEVC are stream-copied
    /// (cheap), while AV1/VP9 are hardware-transcoded to HEVC so every Mac can play the wallpaper.
    /// A no-op when ffmpeg is unavailable (the raw DASH file is used as-is).
    private func normalizeForPlayback(at path: String, ffmpeg: String?, ffprobe: String?) async throws {
        guard let ffmpeg else { return }

        let needsTranscode = await self.needsTranscode(at: path, ffprobe: ffprobe)
        let tmpPath = path + ".normalized.mp4"
        removeItemAtPath(tmpPath)

        let arguments =
            needsTranscode
            ? Self.transcodeArguments(input: path, output: tmpPath)
            : Self.remuxArguments(input: path, output: tmpPath)
        let (status, _, stderr) = try await processRunner(ffmpeg, arguments)

        guard status == 0 else {
            removeItemAtPath(tmpPath)
            throw needsTranscode
                ? YouTubeDownloadError.transcodeFailed(stderr: stderr)
                : YouTubeDownloadError.remuxFailed(stderr: stderr)
        }
        replaceItemAtPath(path, tmpPath)
    }

    /// Whether the downloaded file must be hardware-transcoded to HEVC for universal playback.
    /// Without `ffprobe` we only ever requested the natively-playable AVC stream, so a stream
    /// copy is safe. With `ffprobe` available we transcode AV1/VP9 — and, crucially, also
    /// transcode when codec detection itself *fails*: the `allowAnyCodec` download path may have
    /// produced an AV1/VP9 file, and defaulting a probe failure to a stream copy would silently
    /// leave it unplayable on pre-M3 Apple Silicon / Intel Macs, defeating the every-Mac guarantee.
    func needsTranscode(at path: String, ffprobe: String?) async -> Bool {
        guard ffprobe != nil else { return false }
        let codec = await videoCodec(at: path, ffprobe: ffprobe)
        return codec.map(Self.requiresTranscode) ?? true
    }

    /// The codec name of the first video stream, lowercased, or nil when ffprobe is unavailable or
    /// detection fails (callers then default to a cheap stream copy).
    func videoCodec(at path: String, ffprobe: String?) async -> String? {
        guard let ffprobe else { return nil }
        let arguments = [
            "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=codec_name", "-of", "default=nw=1:nokey=1", path,
        ]
        guard let result = try? await processRunner(ffprobe, arguments), result.status == 0 else {
            return nil
        }
        let codec = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return codec.isEmpty ? nil : codec
    }

    /// AVFoundation cannot decode AV1 (pre-M3) or VP9 (ever), so those must be transcoded.
    static func requiresTranscode(_ codec: String) -> Bool {
        ["av1", "av01", "vp9", "vp09"].contains(codec)
    }

    static func remuxArguments(input: String, output: String) -> [String] {
        ["-nostdin", "-y", "-i", input, "-c", "copy", "-movflags", "+faststart", output]
    }

    static func transcodeArguments(input: String, output: String) -> [String] {
        [
            "-nostdin", "-y", "-i", input, "-an",
            "-c:v", "hevc_videotoolbox", "-tag:v", "hvc1", "-movflags", "+faststart", output,
        ]
    }
}

// The subprocess plumbing that used to live here (an `executeProcess` static with a
// blocking pipe drain and a residual `waitUntilExit()` — the very call #308 removed from
// the lyrics side) moved to `ProcessExecutor` + `DarwinGateway.runProcess` (#340). The
// no-arg init's live `processRunner` now delegates to `@Dependency(\.processExecutor)`.

// MARK: - Errors

public enum YouTubeDownloadError: Error, CustomStringConvertible {
    case toolNotFound
    case downloadFailed(status: Int32, stderr: String)
    case outputNotFound
    case remuxFailed(stderr: String)
    case transcodeFailed(stderr: String)

    public var description: String {
        switch self {
        case .toolNotFound:
            "yt-dlp not found. Install with: brew install yt-dlp (or brew install uv for uvx)"
        case .downloadFailed(let status, let stderr):
            "yt-dlp exited with status \(status)" + (stderr.isEmpty ? "" : "\n\(stderr)")
        case .outputNotFound:
            "yt-dlp completed but output file not found"
        case .remuxFailed(let stderr):
            "ffmpeg remux failed" + (stderr.isEmpty ? "" : "\n\(stderr)")
        case .transcodeFailed(let stderr):
            "ffmpeg HEVC transcode failed" + (stderr.isEmpty ? "" : "\n\(stderr)")
        }
    }
}
