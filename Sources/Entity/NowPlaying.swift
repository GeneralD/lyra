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

public struct NowPlaying {
    public let title: String?
    public let artist: String?
    public let artworkData: Data?
    public let duration: TimeInterval?
    public let rawElapsed: TimeInterval?
    public let playbackRate: Double
    public let timestamp: Date?

    public init(
        title: String?,
        artist: String?,
        artworkData: Data?,
        duration: TimeInterval?,
        rawElapsed: TimeInterval?,
        playbackRate: Double,
        timestamp: Date?
    ) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.duration = duration
        self.rawElapsed = rawElapsed
        self.playbackRate = playbackRate
        self.timestamp = timestamp
    }
}

extension NowPlaying: Sendable {}
extension NowPlaying: Equatable {}

extension NowPlaying {
    public var elapsed: TimeInterval? {
        rawElapsed.map { base in
            guard let ts = timestamp else { return base }
            return base + playbackRate * Date().timeIntervalSince(ts)
        }
    }
}