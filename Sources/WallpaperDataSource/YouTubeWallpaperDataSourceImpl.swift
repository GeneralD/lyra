import Domain
import Foundation

public struct YouTubeWallpaperDataSourceImpl: Sendable {
    public init() {}
}

extension YouTubeWallpaperDataSourceImpl: WallpaperDataSource {
    public func resolve(_ location: YouTubeWallpaper) async throws -> String {
        let cache = try WallpaperCache()

        if let cached = cache.cachedPath(for: location.url, ext: location.format) {
            return cached
        }

        let tool = try detectTool()
        let destPath = cache.destinationPath(for: location.url, ext: location.format)
        let args = buildArgs(tool: tool, url: location.url, maxHeight: location.maxHeight, format: location.format, destPath: destPath)

        let (status, stderr) = try await runProcess(executablePath: tool.executablePath, arguments: args)

        guard status == 0 else {
            throw YouTubeDownloadError.downloadFailed(status: status, stderr: stderr)
        }

        guard FileManager.default.fileExists(atPath: destPath) else {
            throw YouTubeDownloadError.outputNotFound
        }

        try await remuxToStandardMP4(at: destPath)

        return destPath
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Command Building

extension YouTubeWallpaperDataSourceImpl {
    func buildArgs(tool: Tool, url: URL, maxHeight: Int, format: String, destPath: String) -> [String] {
        let ytdlpArgs = [
            "-f", "bestvideo[ext=\(format)][height<=\(maxHeight)][vcodec^=avc]",
            "--no-audio",
            "-o", destPath,
            url.absoluteString,
        ]
        switch tool {
        case .ytdlp: return ytdlpArgs
        case .uvx: return ["yt-dlp"] + ytdlpArgs
        }
    }
}

// MARK: - Remux

extension YouTubeWallpaperDataSourceImpl {
    /// Remux DASH container to standard MP4 for AVPlayer compatibility (loop support).
    private func remuxToStandardMP4(at path: String) async throws {
        guard let ffmpeg = findExecutable("ffmpeg") else { return }
        let tmpPath = path + ".remux.mp4"
        try? FileManager.default.removeItem(atPath: tmpPath)
        let (status, stderr) = try await runProcess(
            executablePath: ffmpeg,
            arguments: ["-y", "-i", path, "-c", "copy", "-movflags", "+faststart", tmpPath]
        )
        guard status == 0 else {
            try? FileManager.default.removeItem(atPath: tmpPath)
            throw YouTubeDownloadError.remuxFailed(stderr: stderr)
        }
        _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmpPath))
    }
}

// MARK: - Async Process

extension YouTubeWallpaperDataSourceImpl {
    private func runProcess(executablePath: String, arguments: [String]) async throws -> (status: Int32, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrString = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: (proc.terminationStatus, stderrString))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Errors

public enum YouTubeDownloadError: Error, CustomStringConvertible {
    case toolNotFound
    case downloadFailed(status: Int32, stderr: String)
    case outputNotFound
    case remuxFailed(stderr: String)

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
        }
    }
}
