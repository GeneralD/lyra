import Dependencies
import Domain
import Foundation

public struct LyricsRepositoryImpl {
    @Dependency(\.lyricsCache) private var cache
    @Dependency(\.lyricsDataSource) private var dataSource
    @Dependency(\.utaNetLyricsDataSource) private var utaNetDataSource
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

        // uta-net matches strictly on normalized title+artist inside get() (and
        // requires a non-empty artist), so no extra validation is needed here.
        if let result = await utaNetDataSource.get(title: track.title, artist: track.artist, duration: track.duration) {
            await store(result, track: track)
            return result
        }

        return nil
    }

    public func fetchLyrics(candidates: [Track]) async -> LyricsResult? {
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            guard let cached = await cache.read(title: candidate.title, artist: candidate.artist) else { continue }
            // Rows written before validation existed (pre-#308 upgrades) can hold lyrics
            // that never matched this candidate — a poisoned entry that would otherwise
            // short-circuit the validated tiers forever. Re-validate on read; an invalid
            // entry is skipped so Tier A/B/C/D can overwrite it with a real match.
            guard validator.isValid(candidate: candidate, result: cached) else { continue }
            return cached
        }

        if let result = await tierAExactMatch(candidates: candidates) {
            return result
        }
        if let result = await tierBValidatedSearch(candidates: candidates) {
            return result
        }
        if let result = await tierCUtaNet(candidates: candidates) {
            return result
        }
        if let result = await tierDCustomScript(candidates: candidates) {
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
            // LRCLIB fuzzy search can return several lyric-bearing results, only some
            // of which pass validation. Validate every candidate response — not just
            // the first — and accept the first valid one (synced preferred over plain)
            // so a noisy leading result can't sink an otherwise-matching later hit.
            let valid = responses.filter { $0.syncedLyrics != nil || $0.plainLyrics != nil }
                .filter { validator.isValid(candidate: c, result: $0) }
            guard let matched = valid.first(where: { $0.syncedLyrics != nil }) ?? valid.first else { continue }
            let displayResult = displayAdjusted(matched, candidate: c)
            await store(displayResult, track: c)
            return displayResult
        }
        return nil
    }
}

// MARK: - Tier C: uta-net (built-in Japanese lyrics site)

extension LyricsRepositoryImpl {
    private func tierCUtaNet(candidates: [Track]) async -> LyricsResult? {
        for c in candidates where !c.artist.isEmpty {
            guard let result = await utaNetDataSource.get(title: c.title, artist: c.artist, duration: c.duration) else {
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

// MARK: - Tier D: user-defined custom script

extension LyricsRepositoryImpl {
    private func tierDCustomScript(candidates: [Track]) async -> LyricsResult? {
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
    // Fill title and artist independently: a Tier D script may return a valid
    // track_name with no artist_name, and the display/cache identity should then take
    // the matched candidate's artist rather than mixing in the raw fallback downstream.
    private func displayAdjusted(_ result: LyricsResult, candidate: Track) -> LyricsResult {
        let title = result.trackName.flatMap { $0.isEmpty ? nil : $0 } ?? candidate.title
        let artist = result.artistName.flatMap { $0.isEmpty ? nil : $0 } ?? candidate.artist
        return result.withDisplay(title: title, artist: artist)
    }

    private func store(_ result: LyricsResult, track: Track) async {
        guard !track.artist.isEmpty else { return }
        try? await cache.write(title: track.title, artist: track.artist, result: result)
    }
}
