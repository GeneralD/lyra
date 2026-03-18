import Domain
import Dependencies
import GRDB

public struct GRDBAIMetadataCache: AIMetadataCacheRepository {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }
}

extension GRDBAIMetadataCache {
    public func read(rawTitle: String, rawArtist: String) async -> ResolvedTrack? {
        try? await dbManager.dbQueue.read { db in
            guard let record = try AIMetadataCacheRecord
                .filter(Column("raw_title") == rawTitle && Column("raw_artist") == rawArtist)
                .fetchOne(db) else { return nil }
            return ResolvedTrack(title: record.resolvedTitle, artist: record.resolvedArtist)
        }
    }

    public func write(rawTitle: String, rawArtist: String, candidate: ResolvedTrack) async throws {
        try await dbManager.dbQueue.write { db in
            let record = AIMetadataCacheRecord(
                rawTitle: rawTitle,
                rawArtist: rawArtist,
                resolvedTitle: candidate.title,
                resolvedArtist: candidate.artist
            )
            try record.save(db, onConflict: .replace)
        }
    }
}

extension GRDBAIMetadataCache: Sendable {}

// MARK: - DependencyKey

extension AIMetadataCacheRepositoryKey: DependencyKey {
    public static let liveValue: any AIMetadataCacheRepository = {
        guard let db = try? DatabaseManager() else { return NoopAIMetadataCacheLive() }
        return GRDBAIMetadataCache(dbManager: db)
    }()
}

private struct NoopAIMetadataCacheLive: AIMetadataCacheRepository {
    func read(rawTitle: String, rawArtist: String) async -> ResolvedTrack? { nil }
    func write(rawTitle: String, rawArtist: String, candidate: ResolvedTrack) async throws {}
}
