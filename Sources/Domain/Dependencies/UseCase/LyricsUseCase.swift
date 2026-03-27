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

public protocol LyricsUseCase: Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult
    func fetchLyrics(candidates: [Track]) async -> LyricsResult
}

public enum LyricsUseCaseKey: TestDependencyKey {
    public static let testValue: any LyricsUseCase = UnimplementedLyricsUseCase()
}

extension DependencyValues {
    public var lyricsUseCase: any LyricsUseCase {
        get { self[LyricsUseCaseKey.self] }
        set { self[LyricsUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedLyricsUseCase: LyricsUseCase {
    func fetchLyrics(track: Track) async -> LyricsResult { .empty }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult { .empty }
}