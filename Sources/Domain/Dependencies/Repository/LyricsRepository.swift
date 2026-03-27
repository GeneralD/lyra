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

public protocol LyricsRepository: Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult?
    func fetchLyrics(candidates: [Track]) async -> LyricsResult?
}

public enum LyricsRepositoryKey: TestDependencyKey {
    public static let testValue: any LyricsRepository = UnimplementedLyricsRepository()
}

extension DependencyValues {
    public var lyricsRepository: any LyricsRepository {
        get { self[LyricsRepositoryKey.self] }
        set { self[LyricsRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedLyricsRepository: LyricsRepository {
    func fetchLyrics(track: Track) async -> LyricsResult? { nil }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult? { nil }
}