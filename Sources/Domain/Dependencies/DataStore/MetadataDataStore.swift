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

public protocol MetadataDataStore<Value>: Sendable {
    associatedtype Value: Sendable
    func read(title: String, artist: String) async -> Value?
    func write(title: String, artist: String, value: Value) async throws
}

// MARK: - LLM Metadata Cache (Track)

public enum LLMMetadataDataStoreKey: TestDependencyKey {
    public static let testValue: any MetadataDataStore<Track> = NoopMetadataDataStore()
}

extension DependencyValues {
    public var llmMetadataDataStore: any MetadataDataStore<Track> {
        get { self[LLMMetadataDataStoreKey.self] }
        set { self[LLMMetadataDataStoreKey.self] = newValue }
    }
}

// MARK: - MusicBrainz Metadata Cache (MusicBrainzMetadata)

public enum MusicBrainzMetadataDataStoreKey: TestDependencyKey {
    public static let testValue: any MetadataDataStore<MusicBrainzMetadata> = NoopMetadataDataStore()
}

extension DependencyValues {
    public var musicBrainzMetadataDataStore: any MetadataDataStore<MusicBrainzMetadata> {
        get { self[MusicBrainzMetadataDataStoreKey.self] }
        set { self[MusicBrainzMetadataDataStoreKey.self] = newValue }
    }
}

// MARK: - Noop

private struct NoopMetadataDataStore<Value: Sendable>: MetadataDataStore {
    func read(title: String, artist: String) async -> Value? { nil }
    func write(title: String, artist: String, value: Value) async throws {}
}