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

public protocol LyricsDataStore: Sendable {
    func read(title: String, artist: String) async -> LyricsResult?
    func write(title: String, artist: String, result: LyricsResult) async throws
}

public enum LyricsDataStoreKey: TestDependencyKey {
    public static let testValue: any LyricsDataStore = UnimplementedLyricsDataStore()
}

extension DependencyValues {
    public var lyricsCache: any LyricsDataStore {
        get { self[LyricsDataStoreKey.self] }
        set { self[LyricsDataStoreKey.self] = newValue }
    }
}

private struct UnimplementedLyricsDataStore: LyricsDataStore {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}