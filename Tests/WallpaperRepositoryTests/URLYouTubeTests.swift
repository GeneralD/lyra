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