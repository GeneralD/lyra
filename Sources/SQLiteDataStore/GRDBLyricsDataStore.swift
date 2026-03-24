import Domain
import GRDB

public struct GRDBLyricsDataStore: LyricsDataStore {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func read(title: String, artist: String) async -> LyricsResult? {
        try? await dbManager.dbQueue.read { db in
            try LRCLibTrackRecord
                .joining(
                    required: LRCLibTrackRecord.lookups
                        .filter(Column("title") == title && Column("artist") == artist)
                )
                .fetchOne(db)?
                .toLyricsResult()
        }
    }

    public func write(title: String, artist: String, result: LyricsResult) async throws {
        guard result.id != nil else { return }
        try await dbManager.dbQueue.write { db in
            let track = LRCLibTrackRecord(from: result)
            try track.save(db, onConflict: .replace)

            let lookup = LyricsLookupRecord(id: nil, title: title, artist: artist, lrclibId: track.id)
            try lookup.save(db, onConflict: .replace)
        }
    }
}

extension GRDBLyricsDataStore: Sendable {}
