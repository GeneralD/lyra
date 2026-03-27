// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
        findExecutableInPath(name)
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
        let hasYtdlp = findExecutableInPath("yt-dlp") != nil
        let downloadChecker: WallpaperToolChecker = hasYtdlp ? .ytdlp : .uvx
        return [downloadChecker, .ffmpeg]
    }
}