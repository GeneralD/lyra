import Domain
import Testing

@testable import WallpaperDataSource

@Suite("WallpaperToolChecker")
struct WallpaperToolCheckerTests {
    @Test("youtubeCheckers prefers yt-dlp when available")
    func prefersYtdlp() async {
        let checkers = WallpaperToolChecker.youtubeCheckers { name in
            switch name {
            case "yt-dlp": "/opt/homebrew/bin/yt-dlp"
            case "ffmpeg": "/opt/homebrew/bin/ffmpeg"
            default: nil
            }
        }

        #expect(checkers.map(\.serviceName) == ["yt-dlp", "ffmpeg"])
        let result = await checkers[0].healthCheck()
        #expect(result.status == .pass)
        #expect(result.detail == "/opt/homebrew/bin/yt-dlp")
    }

    @Test("youtubeCheckers falls back to uvx when yt-dlp is missing")
    func fallsBackToUvx() async {
        let checkers = WallpaperToolChecker.youtubeCheckers { name in
            switch name {
            case "uvx": "/opt/homebrew/bin/uvx"
            default: nil
            }
        }

        #expect(checkers.map(\.serviceName) == ["uvx (yt-dlp)", "ffmpeg"])

        let required = await checkers[0].healthCheck()
        let optional = await checkers[1].healthCheck()
        #expect(required.status == .pass)
        #expect(required.detail == "/opt/homebrew/bin/uvx")
        #expect(optional.status == .skip)
        #expect(optional.detail.contains("optional"))
    }

    @Test("required checker reports install hint when tool is missing")
    func requiredMissing() async {
        let checker = WallpaperToolChecker.youtubeCheckers { _ in nil }[0]

        let result = await checker.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail.contains("install with"))
    }

    @Test("public youtubeCheckers always returns two checkers")
    func publicYoutubeCheckers() {
        let checkers = WallpaperToolChecker.youtubeCheckers()
        #expect(checkers.count == 2)
    }
}
