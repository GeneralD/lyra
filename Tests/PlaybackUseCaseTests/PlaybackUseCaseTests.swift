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

@testable import PlaybackUseCase

@Suite("PlaybackUseCase")
struct PlaybackUseCaseTests {
    @Test("yields NowPlaying values from repository stream")
    func yieldsValues() async {
        let now = Date()
        let infos: [NowPlaying?] = [
            NowPlaying(title: "Song", artist: "Artist", artworkData: nil, duration: 200, rawElapsed: 10, playbackRate: 1.0, timestamp: now),
            nil,
            NowPlaying(title: "Next", artist: "Band", artworkData: nil, duration: 180, rawElapsed: 0, playbackRate: 1.0, timestamp: now),
        ]
        await withDependencies {
            $0.nowPlayingRepository = MockNowPlayingRepository(infos: infos)
        } operation: {
            let useCase = PlaybackUseCaseImpl()
            var collected: [NowPlaying?] = []
            for await value in useCase.observeNowPlaying() {
                collected.append(value)
            }
            #expect(collected.count == infos.count)
            #expect(collected[0]?.title == "Song")
            #expect(collected[1] == nil)
            #expect(collected[2]?.title == "Next")
        }
    }

    @Test("finishes when repository stream is empty")
    func emptyStream() async {
        await withDependencies {
            $0.nowPlayingRepository = MockNowPlayingRepository(infos: [])
        } operation: {
            let useCase = PlaybackUseCaseImpl()
            var collected: [NowPlaying?] = []
            for await value in useCase.observeNowPlaying() {
                collected.append(value)
            }
            #expect(collected.isEmpty)
        }
    }
}

// MARK: - Mocks

private struct MockNowPlayingRepository: NowPlayingRepository {
    let infos: [NowPlaying?]

    func stream() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            for info in infos { continuation.yield(info) }
            continuation.finish()
        }
    }
}