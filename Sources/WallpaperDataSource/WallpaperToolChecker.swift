import Domain
import Foundation

public struct WallpaperToolChecker: HealthCheckable {
    public let serviceName: String
    private let toolName: String
    private let severity: Severity
    private let installHint: String
    private let executableFinder: @Sendable (String) -> String?

    enum Severity { case required, optional }

    private init(
        serviceName: String,
        toolName: String,
        severity: Severity,
        installHint: String? = nil,
        executableFinder: @escaping @Sendable (String) -> String? = findExecutableInPath
    ) {
        self.serviceName = serviceName
        self.toolName = toolName
        self.severity = severity
        self.installHint = installHint ?? "brew install \(toolName)"
        self.executableFinder = executableFinder
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
        executableFinder(name)
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
        youtubeCheckers(findExecutableInPath: findExecutableInPath)
    }

    static func youtubeCheckers(findExecutableInPath: @escaping @Sendable (String) -> String?) -> [WallpaperToolChecker] {
        let hasYtdlp = findExecutableInPath("yt-dlp") != nil
        let downloadChecker: WallpaperToolChecker = hasYtdlp ? .ytdlp : .uvx
        return [
            WallpaperToolChecker(
                serviceName: downloadChecker.serviceName,
                toolName: downloadChecker.toolName,
                severity: downloadChecker.severity,
                installHint: downloadChecker.installHint,
                executableFinder: findExecutableInPath
            ),
            WallpaperToolChecker(
                serviceName: ffmpeg.serviceName,
                toolName: ffmpeg.toolName,
                severity: ffmpeg.severity,
                installHint: ffmpeg.installHint,
                executableFinder: findExecutableInPath
            ),
        ]
    }
}
