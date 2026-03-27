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

public protocol MetadataDataSource<Value>: Sendable {
    associatedtype Value: Sendable
    func resolve(track: Track) async -> [Value]
}

// MARK: - LLM (Track)

public enum LLMMetadataDataSourceKey: TestDependencyKey {
    public static let testValue: any MetadataDataSource<Track> = NoopMetadataDataSource()
}

extension DependencyValues {
    public var llmMetadataDataSource: any MetadataDataSource<Track> {
        get { self[LLMMetadataDataSourceKey.self] }

        set { self[LLMMetadataDataSourceKey.self] = newValue }
    }
}

// MARK: - MusicBrainz (MusicBrainzMetadata)

public enum MusicBrainzMetadataDataSourceKey: TestDependencyKey {
    public static let testValue: any MetadataDataSource<MusicBrainzMetadata> = NoopMetadataDataSource()
}

extension DependencyValues {
    public var musicBrainzMetadataDataSource: any MetadataDataSource<MusicBrainzMetadata> {
        get { self[MusicBrainzMetadataDataSourceKey.self] }
        set { self[MusicBrainzMetadataDataSourceKey.self] = newValue }
    }
}

// MARK: - Regex (Track)

public enum RegexMetadataDataSourceKey: TestDependencyKey {
    public static let testValue: any MetadataDataSource<Track> = NoopMetadataDataSource()
}

extension DependencyValues {
    public var regexMetadataDataSource: any MetadataDataSource<Track> {
        get { self[RegexMetadataDataSourceKey.self] }
        set { self[RegexMetadataDataSourceKey.self] = newValue }
    }
}

// MARK: - Noop

private struct NoopMetadataDataSource<Value: Sendable>: MetadataDataSource {
    func resolve(track: Track) async -> [Value] { [] }
}