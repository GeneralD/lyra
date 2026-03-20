import Alamofire
import Domain
import LRCLibService
import Dependencies
import Foundation

public struct LyricsSearchService: LyricsRepository {
    @Dependency(\.lyricsCache) private var lyricsCache
    @Dependency(\.metadataNormalizers) private var metadataNormalizers

    public init() {}
}

// MARK: - LyricsRepository

extension LyricsSearchService {
    public func resolveMetadata(title: String, artist: String) async -> Track? {
        let rawTrack = Track(title: title, artist: artist)
        for normalizer in metadataNormalizers {
            let candidates = await normalizer.resolve(track: rawTrack)
            guard let first = candidates.first else { continue }
            return first
        }
        return nil
    }

    public func fetchLyrics(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        // Check lyrics cache
        if let cached = await lyricsCache.read(title: title, artist: artist) {
            return cached
        }

        let rawTrack = Track(title: title, artist: artist)
        var fallbackCandidates: [Track] = []

        // Try each normalizer: get candidates → LRCLIB get
        for normalizer in metadataNormalizers {
            let candidates = await normalizer.resolve(track: rawTrack)
            guard !candidates.isEmpty else { continue }
            if let result = await searchWithCandidates(candidates, duration: duration) {
                let displayResult = candidates.first
                    .map { result.withDisplay(title: $0.title, artist: $0.artist) } ?? result
                if !artist.isEmpty {
                    try? await lyricsCache.write(title: title, artist: artist, result: displayResult)
                }
                return displayResult
            }
            if fallbackCandidates.isEmpty {
                fallbackCandidates = candidates
            }
        }

        // LRCLIB search fallback
        let searchCandidates = fallbackCandidates.isEmpty ? [rawTrack] : fallbackCandidates
        if let result = await searchFallback(candidates: searchCandidates) {
            if !artist.isEmpty {
                try? await lyricsCache.write(title: title, artist: artist, result: result)
            }
            return result
        }

        return nil
    }
}

// MARK: - Search helpers

private extension LyricsSearchService {
    func searchWithCandidates(_ candidates: [Track], duration: TimeInterval?) async -> LyricsResult? {
        for c in candidates where !c.artist.isEmpty {
            guard let result = await lrclib(LyricsResult.self, from: .get(title: c.title, artist: c.artist, duration: duration)),
                  result.plainLyrics != nil || result.syncedLyrics != nil
            else { continue }
            return result
        }
        guard !candidates.isEmpty else { return nil }
        return await searchFallback(candidates: candidates)
    }
}

// MARK: - Fallback search

private extension LyricsSearchService {
    func searchFallback(candidates: [Track]) async -> LyricsResult? {
        let matches = await candidates
            .map { $0.artist.isEmpty ? $0.title : "\($0.title) \($0.artist)" }
            .asyncCompactMap { await lrclib([LyricsResult].self, from: .search(query: $0)) }
            .compactMap { response in
                response.first { $0.syncedLyrics != nil } ?? response.first { $0.plainLyrics != nil }
            }
        return matches.first { $0.syncedLyrics != nil }
            ?? matches.first
    }
}

// MARK: - API requests

private extension LyricsSearchService {
    func lrclib<T: Decodable & Sendable>(_ type: T.Type, from api: LRCLibAPI) async -> T? {
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
