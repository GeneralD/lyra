import Domain
import Foundation
import Papyrus

public struct LyricsDataSourceImpl {
    private let api: any LRCLib

    public init() {
        self.init(api: LRCLibAPI(provider: Provider(baseURL: LRCLibAPI.baseURL)))
    }

    init(api: any LRCLib) {
        self.api = api
    }
}

// Safe: `api` is set at init and never mutated; Papyrus's Provider is configured during construction only.
extension LyricsDataSourceImpl: @unchecked Sendable {}

extension LyricsDataSourceImpl: LyricsDataSource {
    public func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        guard let result = try? await api.get(trackName: title, artistName: artist, duration: duration.map(Int.init)),
            result.plainLyrics != nil || result.syncedLyrics != nil
        else { return nil }
        return result
    }

    public func search(query: String) async -> [LyricsResult]? {
        try? await api.search(q: query)
    }
}
