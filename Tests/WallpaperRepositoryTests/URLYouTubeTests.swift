import Foundation
import Testing

@testable import WallpaperRepository

@Suite("URL.isYouTube")
struct URLYouTubeTests {

    @Suite("positive cases")
    struct PositiveCases {
        @Test(
            "recognizes YouTube URLs",
            arguments: [
                URL(string: "https://youtube.com/watch?v=abc123")!,
                URL(string: "https://www.youtube.com/watch?v=abc123")!,
                URL(string: "https://youtu.be/abc123")!,
                URL(string: "https://m.youtube.com/watch?v=abc123")!,
                URL(string: "https://youtube.com")!,
            ])
        func isYouTube(url: URL) {
            #expect(url.isYouTube)
        }
    }

    @Suite("negative cases")
    struct NegativeCases {
        @Test(
            "rejects non-YouTube URLs",
            arguments: [
                URL(string: "https://example.com")!,
                URL(string: "https://youtuber.com")!,
                URL(string: "https://notyoutube.com")!,
                URL(string: "https://youtu.be.evil.com")!,
                URL(string: "file:///path/to/video.mp4")!,
            ])
        func isNotYouTube(url: URL) {
            #expect(!url.isYouTube)
        }
    }
}
