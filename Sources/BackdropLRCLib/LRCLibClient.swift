import BackdropDomain
import CollectionKit
import Dependencies
import Foundation

public struct LRCLibClient: LyricsRepository {
    public init() {}

    public func fetch(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        let parser = TitleParser()
        let candidates = parser.generateCandidates(title: title, artist: artist)

        let getResults = await candidates
            .unless(\.artist.isEmpty)
            .asyncCompactMap { await get(title: $0.title, artist: $0.artist, duration: duration) }
            .filter { $0.plainLyrics != nil }

        if let synced = getResults.first(where: { $0.syncedLyrics != nil }) { return synced }
        if let first = getResults.first { return first }
        return await searchFallback(candidates: candidates)
    }

    private func searchFallback(candidates: [SearchCandidate]) async -> LyricsResult? {
        let searchResults = await candidates
            .map { $0.artist.isEmpty ? $0.title : "\($0.title) \($0.artist)" }
            .asyncCompactMap { await search(query: $0) }
            .filter { $0.plainLyrics != nil }
        return searchResults.first { $0.syncedLyrics != nil }
            ?? searchResults.first
    }

    private func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        let items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            duration.map { URLQueryItem(name: "duration", value: String(Int($0))) },
        ].compactMap { $0 }
        guard let url = buildURL("get", queryItems: items),
              let data = await httpGet(url) else { return nil }
        return try? JSONDecoder().decode(LyricsResult.self, from: data)
    }

    private func search(query: String) async -> LyricsResult? {
        guard let url = buildURL("search", queryItems: [URLQueryItem(name: "q", value: query)]),
              let data = await httpGet(url),
              let results = try? JSONDecoder().decode([LyricsResult].self, from: data) else { return nil }
        return results.first { $0.syncedLyrics != nil }
            ?? results.first { $0.plainLyrics != nil }
    }

    private func buildURL(_ path: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/\(path)")!
        components.queryItems = queryItems
        return components.url
    }

    private func httpGet(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("now-playing/1.0", forHTTPHeaderField: "User-Agent")
        return try? await URLSession.shared.data(for: request).0
    }
}

// MARK: - DependencyKey

extension LyricsRepositoryKey: DependencyKey {
    public static let liveValue: any LyricsRepository = LRCLibClient()
}

// MARK: - Async helpers

private extension Array {
    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var results: [T] = []
        for element in self {
            if let transformed = await transform(element) {
                results.append(transformed)
            }
        }
        return results
    }
}

extension LRCLibClient: Sendable {}
