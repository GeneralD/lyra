import Domain
import Dependencies
import GRDB

public struct GRDBLyricsCache: LyricsDataStore {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func read(title: String, artist: String) async -> LyricsResult? {
        try? await dbManager.dbQueue.read { db in
            let sql = """
                SELECT t.*
                FROM lyrics_lookup l
                JOIN lrclib_tracks t ON l.lrclib_id = t.id
                WHERE l.title = ? AND l.artist = ?
                """
            return try LRCLibTrackRecord
                .fetchOne(db, sql: sql, arguments: [title, artist])?
                .toLyricsResult()
        }
    }

    public func write(title: String, artist: String, result: LyricsResult) async throws {
        guard result.id != nil else { return }
        try await dbManager.dbQueue.write { db in
            let track = LRCLibTrackRecord(from: result)
            try track.save(db, onConflict: .replace)

            var lookup = LyricsLookupRecord(id: nil, title: title, artist: artist, lrclibId: track.id)
            try lookup.save(db, onConflict: .replace)
        }
    }
}

// MARK: - DependencyKey

extension LyricsDataStoreKey: DependencyKey {
    public static let liveValue: any LyricsDataStore = {
        guard let dbManager = try? DatabaseManager() else {
            return NoopLyricsCache()
        }
        return GRDBLyricsCache(dbManager: dbManager)
    }()
}

private struct NoopLyricsCache: LyricsDataStore {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

extension GRDBLyricsCache: Sendable {}
