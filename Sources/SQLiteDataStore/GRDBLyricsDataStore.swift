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