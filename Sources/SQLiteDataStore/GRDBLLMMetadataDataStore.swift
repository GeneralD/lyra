import Domain
import GRDB

public struct GRDBLLMMetadataDataStore: MetadataDataStore {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }
}

extension GRDBLLMMetadataDataStore {
    public func read(title: String, artist: String) async -> Track? {
        try? await dbManager.dbQueue.read { db in
            guard
                let record =
                    try AIMetadataCacheRecord
                    .filter(Column("raw_title") == title && Column("raw_artist") == artist)
                    .fetchOne(db)
            else { return nil }
            return Track(title: record.resolvedTitle, artist: record.resolvedArtist)
        }
    }

    public func write(title: String, artist: String, value: Track) async throws {
        try await dbManager.dbQueue.write { db in
            let record = AIMetadataCacheRecord(
                rawTitle: title,
                rawArtist: artist,
                resolvedTitle: value.title,
                resolvedArtist: value.artist
            )
            try record.save(db, onConflict: .replace)
        }
    }
}

extension GRDBLLMMetadataDataStore: Sendable {}
