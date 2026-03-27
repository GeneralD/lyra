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

public struct MetadataRepositoryImpl {
    @Dependency(\.llmMetadataDataSource) private var llmDataSource
    @Dependency(\.musicBrainzMetadataDataSource) private var musicBrainzDataSource
    @Dependency(\.regexMetadataDataSource) private var regexDataSource
    @Dependency(\.llmMetadataDataStore) private var llmDataStore
    @Dependency(\.musicBrainzMetadataDataStore) private var musicBrainzDataStore

    public init() {}
}

extension MetadataRepositoryImpl: MetadataRepository {
    public func resolve(track: Track) async -> [Track] {
        // 1. LLM cache
        if let cached = await llmDataStore.read(title: track.title, artist: track.artist) {
            return [Track(title: cached.title, artist: cached.artist, duration: track.duration)]
        }

        // 2. LLM DataSource
        let llmCandidates = await llmDataSource.resolve(track: track)
        if let first = llmCandidates.first {
            try? await llmDataStore.write(title: track.title, artist: track.artist, value: first)
            return llmCandidates.map { Track(title: $0.title, artist: $0.artist, duration: track.duration) }
        }

        // 3. MusicBrainz cache
        if let cached = await musicBrainzDataStore.read(title: track.title, artist: track.artist) {
            return [Track(title: cached.title, artist: cached.artist, duration: cached.duration)]
        }

        // 4. MusicBrainz DataSource
        let mbCandidates = await musicBrainzDataSource.resolve(track: track)
        if let first = mbCandidates.first {
            try? await musicBrainzDataStore.write(title: track.title, artist: track.artist, value: first)
            return mbCandidates.map { Track(title: $0.title, artist: $0.artist, duration: $0.duration) }
        }

        // 5. Regex DataSource (no cache)
        return await regexDataSource.resolve(track: track).map {
            Track(title: $0.title, artist: $0.artist, duration: track.duration)
        }
    }
}