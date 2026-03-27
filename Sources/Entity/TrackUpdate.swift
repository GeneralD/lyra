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

public struct TrackUpdate {
    public let title: String?
    public let artist: String?
    public let artworkData: Data?
    public let duration: TimeInterval?
    public let lyrics: LyricsContent?
    public let lyricsState: TrackLyricsState

    public init(
        title: String? = nil,
        artist: String? = nil,
        artworkData: Data? = nil,
        duration: TimeInterval? = nil,
        lyrics: LyricsContent? = nil,
        lyricsState: TrackLyricsState = .idle
    ) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.duration = duration
        self.lyrics = lyrics
        self.lyricsState = lyricsState
    }
}

extension TrackUpdate: Sendable {}