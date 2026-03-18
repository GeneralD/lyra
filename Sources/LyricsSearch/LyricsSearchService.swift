import Alamofire
import CollectionKit
import Domain
import TitleExtraction
import Dependencies
import Foundation

public struct LyricsSearchService: LyricsRepository {
    @Dependency(\.metadataCache) private var metadataCache
    @Dependency(\.lyricsCache) private var lyricsCache
    @Dependency(\.titleExtractors) private var titleExtractors

    public init() {}
}

// MARK: - LyricsRepository

extension LyricsSearchService {
    public func resolveMetadata(title: String, artist: String) async -> ResolvedTrack? {
        for extractor in titleExtractors {
            let candidates = await extractor.extract(rawTitle: title, rawArtist: artist)
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

        // Resolve candidates for search
        var allCandidates: [ResolvedTrack] = []
        for extractor in titleExtractors {
            let candidates = await extractor.extract(rawTitle: title, rawArtist: artist)
            guard !candidates.isEmpty else { continue }
            allCandidates = candidates
            break
        }

        // Search with resolved candidates
        if let result = await searchWithCandidates(allCandidates, duration: duration) {
            let displayResult = allCandidates.first
                .map { result.withDisplay(title: $0.title, artist: $0.artist) } ?? result
            if !artist.isEmpty {
                try? await lyricsCache.write(title: title, artist: artist, result: displayResult)
            }
            return displayResult
        }

        // MusicBrainz fallback
        if let result = await fetchViaMusicBrainz(title: title, artist: artist, duration: duration) {
            if !artist.isEmpty {
                try? await lyricsCache.write(title: title, artist: artist, result: result)
            }
            return result
        }

        // Regex free-text search fallback
        let regexCandidates = RegexTitleExtractor().generateCandidates(title: title, artist: artist)
        if let result = await searchFallback(candidates: regexCandidates) {
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
    func searchWithCandidates(_ candidates: [ResolvedTrack], duration: TimeInterval?) async -> LyricsResult? {
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

// MARK: - MusicBrainz → LRCLIB pipeline

private extension LyricsSearchService {
    func fetchViaMusicBrainz(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        let parser = RegexTitleExtractor()
        let parsed = parser.parseArtistTitle(title)
        let normalized = parsed.title
        let normalizedArtist = parser.normalizeArtist(parsed.artist ?? artist)

        if let cached = await metadataCache.read(title: normalized, artist: normalizedArtist) {
            let result = await lrclib(LyricsResult.self, from: .get(
                title: cached.title, artist: cached.artist, duration: cached.duration
            ))
            if let result, result.plainLyrics != nil || result.syncedLyrics != nil {
                return result
            }
        }

        for query: MusicBrainzAPI in [
            .searchRecording(title: normalized, artist: normalizedArtist, duration: duration),
            .searchRecording(title: normalized, artist: nil, duration: nil),
        ] {
            guard let response: MusicBrainzResponse = await musicbrainz(query) else { continue }
            if let result = await matchRecording(from: response, cacheKey: (normalized, normalizedArtist)) {
                return result
            }
        }
        return nil
    }

    func matchRecording(from response: MusicBrainzResponse, cacheKey: (title: String, artist: String)) async -> LyricsResult? {
        let parser = RegexTitleExtractor()
        for recording in response.recordings {
            guard let artistName = recording.artistName else { continue }
            var seen = Set<String>()
            let titles = [recording.title, parser.normalize(recording.title), parser.stripBrackets(recording.title)]
                .filter { seen.insert($0).inserted }
            for title in titles {
                let result = await lrclib(LyricsResult.self, from: .get(
                    title: title, artist: artistName, duration: recording.duration
                ))
                guard let result, result.plainLyrics != nil || result.syncedLyrics != nil else { continue }

                let metadata = ResolvedMetadata(
                    title: title, artist: artistName,
                    duration: recording.duration, musicbrainzId: recording.id
                )
                try? await metadataCache.write(queryTitle: cacheKey.title, queryArtist: cacheKey.artist, metadata: metadata)
                return result
            }
        }
        return nil
    }
}

// MARK: - Fallback search

private extension LyricsSearchService {
    func searchFallback(candidates: [ResolvedTrack]) async -> LyricsResult? {
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

    func musicbrainz<T: Decodable & Sendable>(_ api: MusicBrainzAPI) async -> T? {
        await AF.request(api)
            .validate(statusCode: 200 ..< 300)
            .serializingDecodable(T.self)
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
