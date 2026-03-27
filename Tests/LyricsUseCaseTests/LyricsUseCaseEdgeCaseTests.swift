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

import Dependencies
import Foundation
import Testing

@testable import Domain
@testable import LyricsUseCase

@Suite("LyricsUseCase edge cases")
struct LyricsUseCaseEdgeCaseTests {

    @Test("fetchLyrics with empty candidates returns .empty")
    func emptyCandidatesReturnsEmpty() async {
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(lyrics: nil)
        } operation: {
            let useCase = LyricsUseCaseImpl()
            let result = await useCase.fetchLyrics(candidates: [])
            #expect(result == .empty)
        }
    }

    @Test("fetchLyrics(track:) passes track directly to repository")
    func fetchLyricsTrackDelegatesToRepository() async {
        let expected = LyricsResult(trackName: "Specific", artistName: "Artist", syncedLyrics: "[00:05.00] Line")
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(lyrics: expected)
        } operation: {
            let useCase = LyricsUseCaseImpl()
            let result = await useCase.fetchLyrics(track: Track(title: "Specific", artist: "Artist", duration: 200))
            #expect(result.trackName == "Specific")
            #expect(result.artistName == "Artist")
            #expect(result.syncedLyrics == "[00:05.00] Line")
        }
    }

    @Test("fetchLyrics(candidates:) passes candidates directly to repository")
    func fetchLyricsCandidatesDelegatesToRepository() async {
        let expected = LyricsResult(id: 42, syncedLyrics: "[00:01.00] Multi")
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(lyrics: expected)
        } operation: {
            let useCase = LyricsUseCaseImpl()
            let result = await useCase.fetchLyrics(candidates: [
                Track(title: "A", artist: "X"),
                Track(title: "B", artist: "Y"),
            ])
            #expect(result.id == 42)
            #expect(result.syncedLyrics == "[00:01.00] Multi")
        }
    }

    @Test("result is never modified — repository value is returned identically")
    func resultPassedThroughUnmodified() async {
        let repositoryResult = LyricsResult(
            id: 99,
            trackName: "Original Title",
            artistName: "Original Artist",
            albumName: "Original Album",
            duration: 300,
            instrumental: false,
            plainLyrics: "Plain text lyrics",
            syncedLyrics: "[00:01.00] Synced lyrics"
        )

        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(lyrics: repositoryResult)
        } operation: {
            let useCase = LyricsUseCaseImpl()
            let result = await useCase.fetchLyrics(track: Track(title: "Anything", artist: "Anyone"))
            #expect(result == repositoryResult)
        }
    }
}

private struct MockLyricsRepository: LyricsRepository {
    let lyrics: LyricsResult?
    func fetchLyrics(track: Track) async -> LyricsResult? { lyrics }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult? { lyrics }
}