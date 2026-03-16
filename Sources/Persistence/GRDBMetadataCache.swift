import Domain
import Dependencies
import GRDB

public struct GRDBMetadataCache: MetadataCacheRepository {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }
}

extension GRDBMetadataCache {
    public func read(title: String, artist: String) async -> ResolvedMetadata? {
        try? await dbManager.dbQueue.read { db in
            guard let record = try MusicBrainzCacheRecord
                .filter(Column("query_title") == title && Column("query_artist") == artist)
                .fetchOne(db) else { return nil }
            return ResolvedMetadata(
                title: record.resolvedTitle,
                artist: record.resolvedArtist,
                duration: record.duration,
                musicbrainzId: record.musicbrainzId
            )
        }
    }

    public func write(queryTitle: String, queryArtist: String, metadata: ResolvedMetadata) async throws {
        try await dbManager.dbQueue.write { db in
            var record = MusicBrainzCacheRecord(
                queryTitle: queryTitle,
                queryArtist: queryArtist,
                resolvedTitle: metadata.title,
                resolvedArtist: metadata.artist,
                duration: metadata.duration,
                musicbrainzId: metadata.musicbrainzId
            )
            try record.save(db, onConflict: .replace)
        }
    }
}

extension GRDBMetadataCache: Sendable {}

// MARK: - DependencyKey

extension MetadataCacheRepositoryKey: DependencyKey {
    public static let liveValue: any MetadataCacheRepository = {
        guard let db = try? DatabaseManager() else { return NoopMetadataCacheLive() }
        return GRDBMetadataCache(dbManager: db)
    }()
}

private struct NoopMetadataCacheLive: MetadataCacheRepository {
    func read(title: String, artist: String) async -> ResolvedMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: ResolvedMetadata) async throws {}
}
