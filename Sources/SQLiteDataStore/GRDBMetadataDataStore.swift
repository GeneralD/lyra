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

import Domain
import GRDB

public struct GRDBMetadataDataStore: MetadataDataStore {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }
}

extension GRDBMetadataDataStore {
    public func read(title: String, artist: String) async -> MusicBrainzMetadata? {
        try? await dbManager.dbQueue.read { db in
            guard
                let record =
                    try MusicBrainzCacheRecord
                    .filter(Column("query_title") == title && Column("query_artist") == artist)
                    .fetchOne(db)
            else { return nil }
            return MusicBrainzMetadata(
                title: record.resolvedTitle,
                artist: record.resolvedArtist,
                duration: record.duration,
                musicbrainzId: record.musicbrainzId
            )
        }
    }

    public func write(title: String, artist: String, value: MusicBrainzMetadata) async throws {
        try await dbManager.dbQueue.write { db in
            let record = MusicBrainzCacheRecord(
                queryTitle: title,
                queryArtist: artist,
                resolvedTitle: value.title,
                resolvedArtist: value.artist,
                duration: value.duration,
                musicbrainzId: value.musicbrainzId
            )
            try record.save(db, onConflict: .replace)
        }
    }
}

extension GRDBMetadataDataStore: Sendable {}