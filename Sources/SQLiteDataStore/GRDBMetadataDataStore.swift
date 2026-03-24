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
