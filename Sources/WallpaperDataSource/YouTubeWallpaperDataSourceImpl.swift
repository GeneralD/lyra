import Dependencies
import Domain
import Foundation

public struct YouTubeWallpaperDataSourceImpl: Sendable {
    @Dependency(\.processGateway) private var gateway
    let tempPathFor: @Sendable (URL, String?) throws -> String
    let processRunner: @Sendable (String, [String]) async throws -> (status: Int32, stderr: String)
    let fileExistsAtPath: @Sendable (String) -> Bool
    let removeItemAtPath: @Sendable (String) -> Void
    let replaceItemAtPath: @Sendable (String, String) -> Void

    public init() {
        self.init(
            tempPathFor: { url, ext in
                try WallpaperCache().tempPath(for: url, ext: ext)
            },
            processRunner: { executablePath, arguments in
                try await Self.executeProcess(executablePath: executablePath, arguments: arguments)
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
        processRunner: @escaping @Sendable (String, [String]) async throws -> (status: Int32, stderr: String),
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
    /// Downloads and remuxes to a temp file in the cache folder. Returns the temp file path.
    /// Cache deduplication is handled by WallpaperRepository.
    public func resolve(_ location: YouTubeWallpaper) async throws -> String {
        let tempPath = try tempPathFor(location.url, location.format)

        let tool = try detectTool()
        let args = buildArgs(
            tool: tool, url: location.url, maxHeight: location.maxHeight,
            format: location.format, destPath: tempPath)

        let (status, stderr) = try await processRunner(tool.executablePath, args)

        guard status == 0 else {
            throw YouTubeDownloadError.downloadFailed(status: status, stderr: stderr)
        }

        guard fileExistsAtPath(tempPath) else {
            throw YouTubeDownloadError.outputNotFound
        }

        try await remuxToStandardMP4(at: tempPath)

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
        removeItemAtPath(tmpPath)
        let (status, stderr) = try await processRunner(
            ffmpeg,
            ["-y", "-i", path, "-c", "copy", "-movflags", "+faststart", tmpPath]
        )
        guard status == 0 else {
            removeItemAtPath(tmpPath)
            throw YouTubeDownloadError.remuxFailed(stderr: stderr)
        }
        replaceItemAtPath(path, tmpPath)
    }
}

// MARK: - Async Process

extension YouTubeWallpaperDataSourceImpl {
    static func executeProcess(executablePath: String, arguments: [String]) async throws -> (status: Int32, stderr: String) {
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
