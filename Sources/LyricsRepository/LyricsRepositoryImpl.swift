import Dependencies
import Domain
import Foundation

public struct LyricsRepositoryImpl {
    @Dependency(\.lyricsCache) private var cache
    @Dependency(\.lyricsDataSource) private var dataSource

    public init() {}
}

extension LyricsRepositoryImpl: LyricsRepository {
    public func fetchLyrics(track: Track) async -> LyricsResult? {
        if let cached = await cache.read(title: track.title, artist: track.artist) {
            return cached
        }

        if let result = await dataSource.get(title: track.title, artist: track.artist, duration: track.duration) {
            await store(result, track: track)
            return result
        }

        let query = track.artist.isEmpty ? track.title : "\(track.title) \(track.artist)"
        if let results = await dataSource.search(query: query),
            let result = results.first(where: { $0.syncedLyrics != nil }) ?? results.first(where: { $0.plainLyrics != nil })
        {
            await store(result, track: track)
            return result
        }

        return nil
    }

    public func fetchLyrics(candidates: [Track]) async -> LyricsResult? {
        guard let first = candidates.first else { return nil }

        if let cached = await cache.read(title: first.title, artist: first.artist) {
            return cached
        }

        for c in candidates where !c.artist.isEmpty {
            guard let result = await dataSource.get(title: c.title, artist: c.artist, duration: c.duration) else { continue }
            let displayResult = result.withDisplay(title: first.title, artist: first.artist)
            await store(displayResult, track: first)
            return displayResult
        }

        let matches =
            await candidates
            .map { $0.artist.isEmpty ? $0.title : "\($0.title) \($0.artist)" }
            .asyncCompactMap { await dataSource.search(query: $0) }
            .compactMap { response in
                response.first { $0.syncedLyrics != nil } ?? response.first { $0.plainLyrics != nil }
            }
        let result = matches.first { $0.syncedLyrics != nil } ?? matches.first
        if let result {
            await store(result, track: first)
        }
        return result
    }
}

// MARK: - Private

extension LyricsRepositoryImpl {
    fileprivate func store(_ result: LyricsResult, track: Track) async {
        guard !track.artist.isEmpty else { return }
        try? await cache.write(title: track.title, artist: track.artist, result: result)
    }
}

extension Array {
    fileprivate func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var results: [T] = []
        for element in self {
            guard let value = await transform(element) else { continue }
            results.append(value)
        }
        return results
    }
}
