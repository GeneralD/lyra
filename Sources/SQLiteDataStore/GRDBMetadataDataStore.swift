import Domain
import GRDB

public struct GRDBMetadataDataStore: MetadataDataStore {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }
}

extension GRDBMetadataDataStore {
    // The cache stores EVERY candidate recording per query (one row each, id order) —
    // the lyrics flow can cache a hit under any MusicBrainz candidate, so a cache hit
    // must reproduce the same candidate set the original API response yielded, or
    // lyrics cached under a later candidate become unreachable on subsequent plays.
    public func read(title: String, artist: String) async -> [MusicBrainzMetadata]? {
        let records = try? await dbManager.dbQueue.read { db in
            try MusicBrainzCacheRecord
                .filter(Column("query_title") == title && Column("query_artist") == artist)
                .order(Column("id"))
                .fetchAll(db)
        }
        guard let records, !records.isEmpty else { return nil }
        return records.map {
            MusicBrainzMetadata(
                title: $0.resolvedTitle,
                artist: $0.resolvedArtist,
                duration: $0.duration,
                musicbrainzId: $0.musicbrainzId
            )
        }
    }

    public func write(title: String, artist: String, value: [MusicBrainzMetadata]) async throws {
        try await dbManager.dbQueue.write { db in
            try MusicBrainzCacheRecord
                .filter(Column("query_title") == title && Column("query_artist") == artist)
                .deleteAll(db)
            for candidate in value {
                let record = MusicBrainzCacheRecord(
                    queryTitle: title,
                    queryArtist: artist,
                    resolvedTitle: candidate.title,
                    resolvedArtist: candidate.artist,
                    duration: candidate.duration,
                    musicbrainzId: candidate.musicbrainzId
                )
                try record.save(db)
            }
        }
    }
}

extension GRDBMetadataDataStore: Sendable {}
