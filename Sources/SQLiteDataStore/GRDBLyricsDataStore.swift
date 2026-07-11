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
        // Tier C custom-script results carry no LRCLIB id — store them under a stable
        // synthetic NEGATIVE id so they are cacheable without ever colliding with a
        // genuine (positive) LRCLIB row. Id-less results with no lyrics content stay
        // unstored: there is nothing to serve on a future hit.
        guard result.id != nil || result.plainLyrics != nil || result.syncedLyrics != nil else { return }
        let track = LRCLibTrackRecord(from: result, id: result.id ?? syntheticId(for: result, title: title, artist: artist))
        try await dbManager.dbQueue.write { db in
            try track.save(db, onConflict: .replace)

            let lookup = LyricsLookupRecord(id: nil, title: title, artist: artist, lrclibId: track.id)
            try lookup.save(db, onConflict: .replace)
        }
    }
}

extension GRDBLyricsDataStore {
    // FNV-1a over the result's display identity, negated into the negative id space.
    // Stable across runs so a re-resolved script result overwrites its own row instead
    // of accreting; a 63-bit space makes collisions negligible for a lyrics cache.
    private func syntheticId(for result: LyricsResult, title: String, artist: String) -> Int {
        let key = "\(result.trackName ?? title)\u{0}\(result.artistName ?? artist)"
        let hash = key.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 }
        let magnitude = Int(hash & 0x7fff_ffff_ffff_ffff)
        return magnitude == 0 ? -1 : -magnitude
    }
}

extension GRDBLyricsDataStore: Sendable {}
