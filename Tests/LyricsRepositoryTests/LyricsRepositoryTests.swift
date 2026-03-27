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
import Domain
import Foundation
import Testing

@testable import LyricsRepository

@Suite("LyricsRepository")
struct LyricsRepositoryTests {

    @Suite("cache behavior")
    struct CacheBehavior {
        @Test("cache hit returns cached result without calling DataSource")
        func cacheHitReturns() async {
            let cached = LyricsResult(
                trackName: "Cached Title", artistName: "Cached Artist",
                syncedLyrics: "[00:01.00] Hello"
            )

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: cached)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(track: Track(title: "any", artist: "any"))
                #expect(result?.trackName == "Cached Title")
                #expect(result?.syncedLyrics == "[00:01.00] Hello")
            }
        }

        @Test("cache hit with candidates returns cached result")
        func cacheHitWithCandidates() async {
            let cached = LyricsResult(syncedLyrics: "[00:01.00] Cached")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: cached)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "First", artist: "Artist"),
                    Track(title: "Second", artist: "Artist"),
                ])
                #expect(result?.syncedLyrics == "[00:01.00] Cached")
            }
        }

        @Test("cache miss returns nil when no lyrics found")
        func cacheMissNoLyrics() async {
            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(
                    track: Track(title: "zzz_nonexistent_zzz", artist: "zzz_nobody_zzz")
                )
                #expect(result == nil)
            }
        }

        @Test("empty candidates returns nil")
        func emptyCandidates() async {
            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [])
                #expect(result == nil)
            }
        }
    }
}

// MARK: - Test helpers

private struct StubLyricsCache: LyricsDataStore {
    let stored: LyricsResult?
    func read(title: String, artist: String) async -> LyricsResult? { stored }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}