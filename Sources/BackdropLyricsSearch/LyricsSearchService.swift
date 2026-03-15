import Alamofire
import BackdropDomain
import CollectionKit
import Dependencies
import Foundation

public struct LyricsSearchService: LyricsRepository {
    public init() {}
}

extension LyricsSearchService {
    public func fetch(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        let candidates = TitleParser().generateCandidates(title: title, artist: artist)

        let getResults = await candidates
            .unless(\.artist.isEmpty)
            .asyncCompactMap { c in await request(LyricsResult.self, from: .get(title: c.title, artist: c.artist, duration: duration)) }
            .filter { $0.plainLyrics != nil || $0.syncedLyrics != nil }

        if let synced = getResults.first(where: { $0.syncedLyrics != nil }) { return synced }
        if let first = getResults.first { return first }
        return await searchFallback(candidates: candidates)
    }
}

private extension LyricsSearchService {
    func searchFallback(candidates: [SearchCandidate]) async -> LyricsResult? {
        let matches = await candidates
            .map { $0.artist.isEmpty ? $0.title : "\($0.title) \($0.artist)" }
            .asyncCompactMap { await request([LyricsResult].self, from: .search(query: $0)) }
            .compactMap { response in
                response.first { $0.syncedLyrics != nil } ?? response.first { $0.plainLyrics != nil }
            }
        return matches.first { $0.syncedLyrics != nil }
            ?? matches.first
    }

    func request<T: Decodable & Sendable>(_ type: T.Type, from api: LRCLibAPI) async -> T? {
        await AF.request(api)
            .validate(statusCode: 200 ..< 300)
            .serializingDecodable(type)
            .response.value
    }
}

// MARK: - DependencyKey

extension LyricsRepositoryKey: DependencyKey {
    public static let liveValue: any LyricsRepository = LyricsSearchService()
}

extension LyricsSearchService: Sendable {}

// MARK: - Async helpers

private extension Array {
    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var results: [T] = []
        for element in self {
            guard let value = await transform(element) else { continue }
            results.append(value)
        }
        return results
    }
}
