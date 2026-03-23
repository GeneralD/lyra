import Dependencies
import Domain
import Foundation
import LyricsDataSource

public struct LyricsRepositoryImpl: LyricsRepository {
    @Dependency(\.lyricsCache) private var cache

    private let dataSource = LyricsSearchService()

    public init() {}

    public func fetchLyrics(track: Track, duration: TimeInterval?) async -> LyricsResult? {
        // Check cache
        if let cached = await cache.read(title: track.title, artist: track.artist) {
            return cached
        }

        // Try exact get
        if let result = await dataSource.get(title: track.title, artist: track.artist, duration: duration) {
            await store(result, title: track.title, artist: track.artist)
            return result
        }

        // Fallback: free-text search
        let query = track.artist.isEmpty ? track.title : "\(track.title) \(track.artist)"
        if let results = await dataSource.search(query: query),
           let result = results.first(where: { $0.syncedLyrics != nil }) ?? results.first(where: { $0.plainLyrics != nil }) {
            await store(result, title: track.title, artist: track.artist)
            return result
        }

        return nil
    }

    public func fetchLyrics(candidates: [Track], duration: TimeInterval?) async -> LyricsResult? {
        // Check cache with first candidate
        if let first = candidates.first,
           let cached = await cache.read(title: first.title, artist: first.artist) {
            return cached
        }

        // Try each candidate with exact get
        for c in candidates where !c.artist.isEmpty {
            guard let result = await dataSource.get(title: c.title, artist: c.artist, duration: duration) else { continue }
            let displayResult = candidates.first
                .map { result.withDisplay(title: $0.title, artist: $0.artist) } ?? result
            if let first = candidates.first {
                await store(displayResult, title: first.title, artist: first.artist)
            }
            return displayResult
        }

        // Fallback: free-text search with all candidates
        let matches = await candidates
            .map { $0.artist.isEmpty ? $0.title : "\($0.title) \($0.artist)" }
            .asyncCompactMap { await dataSource.search(query: $0) }
            .compactMap { response in
                response.first { $0.syncedLyrics != nil } ?? response.first { $0.plainLyrics != nil }
            }
        let result = matches.first { $0.syncedLyrics != nil } ?? matches.first
        if let result, let first = candidates.first {
            await store(result, title: first.title, artist: first.artist)
        }
        return result
    }
}

private extension LyricsRepositoryImpl {
    func store(_ result: LyricsResult, title: String, artist: String) async {
        guard !artist.isEmpty else { return }
        try? await cache.write(title: title, artist: artist, result: result)
    }
}

// MARK: - DependencyKey

extension LyricsRepositoryKey: DependencyKey {
    public static let liveValue: any LyricsRepository = LyricsRepositoryImpl()
}

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
