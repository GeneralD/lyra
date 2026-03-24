import Dependencies
import Domain
import SQLiteDataStore

private enum SharedDatabaseManager {
    static let instance: DatabaseManager? = try? DatabaseManager()
}

extension AIMetadataDataStoreKey: DependencyKey {
    public static let liveValue: any AIMetadataDataStore = {
        guard let db = SharedDatabaseManager.instance else { return NoopAIMetadataDataStore() }
        return GRDBAIMetadataCache(dbManager: db)
    }()
}

extension LyricsDataStoreKey: DependencyKey {
    public static let liveValue: any LyricsDataStore = {
        guard let db = SharedDatabaseManager.instance else { return NoopLyricsDataStore() }
        return GRDBLyricsCache(dbManager: db)
    }()
}

extension MetadataDataStoreKey: DependencyKey {
    public static let liveValue: any MetadataDataStore = {
        guard let db = SharedDatabaseManager.instance else { return NoopMetadataDataStore() }
        return GRDBMetadataCache(dbManager: db)
    }()
}

// MARK: - Noop fallbacks

private struct NoopAIMetadataDataStore: AIMetadataDataStore {
    func read(rawTitle: String, rawArtist: String) async -> Track? { nil }
    func write(rawTitle: String, rawArtist: String, candidate: Track) async throws {}
}

private struct NoopLyricsDataStore: LyricsDataStore {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

private struct NoopMetadataDataStore: MetadataDataStore {
    func read(title: String, artist: String) async -> MusicBrainzMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: MusicBrainzMetadata) async throws {}
}
