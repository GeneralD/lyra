import Dependencies
import Domain
import Foundation

public struct LyricsRepositoryImpl {
    @Dependency(\.lyricsCache) private var cache
    @Dependency(\.lyricsDataSource) private var dataSource
    @Dependency(\.customScriptLyricsDataSource) private var customScriptDataSource
    private let validator = LyricsMatchValidator()

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
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            if let cached = await cache.read(title: candidate.title, artist: candidate.artist) {
                return cached
            }
        }

        if let result = await tierAExactMatch(candidates: candidates) {
            return result
        }
        if let result = await tierBValidatedSearch(candidates: candidates) {
            return result
        }
        if let result = await tierCCustomScript(candidates: candidates) {
            return result
        }
        return nil
    }
}

// MARK: - Tier A: LRCLIB exact match

extension LyricsRepositoryImpl {
    private func tierAExactMatch(candidates: [Track]) async -> LyricsResult? {
        for c in candidates where !c.artist.isEmpty {
            guard let result = await dataSource.get(title: c.title, artist: c.artist, duration: c.duration) else { continue }
            let displayResult = displayAdjusted(result, candidate: c)
            await store(displayResult, track: c)
            return displayResult
        }
        return nil
    }
}

// MARK: - Tier B: LRCLIB fuzzy search + validation

extension LyricsRepositoryImpl {
    private func tierBValidatedSearch(candidates: [Track]) async -> LyricsResult? {
        for c in candidates {
            let query = c.artist.isEmpty ? c.title : "\(c.title) \(c.artist)"
            guard let responses = await dataSource.search(query: query) else { continue }
            guard
                let matched = responses.first(where: { $0.syncedLyrics != nil })
                    ?? responses.first(where: { $0.plainLyrics != nil })
            else { continue }
            guard validator.isValid(candidate: c, result: matched) else { continue }
            let displayResult = displayAdjusted(matched, candidate: c)
            await store(displayResult, track: c)
            return displayResult
        }
        return nil
    }
}

// MARK: - Tier C: user-defined custom script

extension LyricsRepositoryImpl {
    private func tierCCustomScript(candidates: [Track]) async -> LyricsResult? {
        for c in candidates where !c.artist.isEmpty {
            guard let result = await customScriptDataSource.get(title: c.title, artist: c.artist, duration: c.duration) else {
                continue
            }
            guard validator.isValid(candidate: c, result: result) else { continue }
            let displayResult = displayAdjusted(result, candidate: c)
            await store(displayResult, track: c)
            return displayResult
        }
        return nil
    }
}

// MARK: - Private

extension LyricsRepositoryImpl {
    private func displayAdjusted(_ result: LyricsResult, candidate: Track) -> LyricsResult {
        (result.trackName?.isEmpty ?? true) ? result.withDisplay(title: candidate.title, artist: candidate.artist) : result
    }

    private func store(_ result: LyricsResult, track: Track) async {
        guard !track.artist.isEmpty else { return }
        try? await cache.write(title: track.title, artist: track.artist, result: result)
    }
}
