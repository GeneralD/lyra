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

public protocol LyricsDataSource: Sendable {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult?
    func search(query: String) async -> [LyricsResult]?
}

public enum LyricsDataSourceKey: TestDependencyKey {
    public static let testValue: any LyricsDataSource = UnimplementedLyricsDataSource()
}

extension DependencyValues {
    public var lyricsDataSource: any LyricsDataSource {
        get { self[LyricsDataSourceKey.self] }
        set { self[LyricsDataSourceKey.self] = newValue }
    }
}

private struct UnimplementedLyricsDataSource: LyricsDataSource {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { nil }
    func search(query: String) async -> [LyricsResult]? { nil }
}