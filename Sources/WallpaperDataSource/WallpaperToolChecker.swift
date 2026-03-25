import Domain
import Foundation

public struct WallpaperToolChecker: HealthCheckable {
    public let serviceName: String
    private let toolName: String
    private let severity: Severity
    private let installHint: String

    enum Severity { case required, optional }

    private init(serviceName: String, toolName: String, severity: Severity, installHint: String? = nil) {
        self.serviceName = serviceName
        self.toolName = toolName
        self.severity = severity
        self.installHint = installHint ?? "brew install \(toolName)"
    }

    public func healthCheck() async -> HealthCheckResult {
        guard let path = findExecutable(toolName) else {
            switch severity {
            case .required:
                return HealthCheckResult(status: .fail, detail: "not found — install with: \(installHint)")
            case .optional:
                return HealthCheckResult(status: .skip, detail: "not found (optional — YouTube wallpaper may not loop)")
            }
        }
        return HealthCheckResult(status: .pass, detail: path)
    }

    private func findExecutable(_ name: String) -> String? {
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

extension WallpaperToolChecker {
    public static let ytdlp = WallpaperToolChecker(
        serviceName: "yt-dlp",
        toolName: "yt-dlp",
        severity: .required
    )

    public static let uvx = WallpaperToolChecker(
        serviceName: "uvx (yt-dlp)",
        toolName: "uvx",
        severity: .required,
        installHint: "brew install uv"
    )

    public static let ffmpeg = WallpaperToolChecker(
        serviceName: "ffmpeg",
        toolName: "ffmpeg",
        severity: .optional
    )

    /// Returns checkers for YouTube wallpaper tools.
    /// yt-dlp is checked first; if not found, uvx is checked as alternative.
    public static func youtubeCheckers() -> [WallpaperToolChecker] {
        let hasYtdlp = WallpaperToolChecker.ytdlp.findExecutable("yt-dlp") != nil
        let downloadChecker: WallpaperToolChecker = hasYtdlp ? .ytdlp : .uvx
        return [downloadChecker, .ffmpeg]
    }
}
