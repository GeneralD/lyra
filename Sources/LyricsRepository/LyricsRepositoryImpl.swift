import Dependencies
import Domain
import Foundation

public struct LyricsRepositoryImpl {
    @Dependency(\.lyricsCache) private var cache
    @Dependency(\.lyricsDataSource) private var dataSource
    @Dependency(\.customScriptLyricsDataSource) private var customScriptDataSource
    @Dependency(\.lyricsResolutionLog) private var resolutionLog
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

        // The decision trace (#331) is purely additive: it never changes which result
        // is returned. When the log is disabled `tracing` is false and no trace string
        // is built, so a disabled log costs nothing on this path.
        let tracing = resolutionLog.isEnabled
        var trace = tracing ? traceHeader(candidates) : []

        for candidate in candidates {
            guard let cached = await cache.read(title: candidate.title, artist: candidate.artist) else { continue }
            // Rows written before validation existed (pre-#308 upgrades) can hold lyrics
            // that never matched this candidate — a poisoned entry that would otherwise
            // short-circuit the validated tiers forever. Re-validate on read; an invalid
            // entry is skipped so Tier A/B/C can overwrite it with a real match.
            if validator.isValid(candidate: candidate, result: cached) {
                if tracing {
                    trace.append("cache HIT  \(describe(candidate)) -> \(describe(cached))")
                    flush(trace, outcome: "cache")
                }
                return cached
            }
            if tracing {
                trace.append(
                    "cache REJECT \(describe(candidate)) -> \(describe(cached))  [\(rejectReason(candidate, cached))]")
            }
        }

        let a = await tierAExactMatch(candidates: candidates, tracing: tracing)
        trace += a.trace
        if let result = a.result {
            if tracing { flush(trace, outcome: "tierA") }
            return result
        }

        let b = await tierBValidatedSearch(candidates: candidates, tracing: tracing)
        trace += b.trace
        if let result = b.result {
            if tracing { flush(trace, outcome: "tierB") }
            return result
        }

        let c = await tierCCustomScript(candidates: candidates, tracing: tracing)
        trace += c.trace
        if let result = c.result {
            if tracing { flush(trace, outcome: "tierC") }
            return result
        }

        if tracing { flush(trace, outcome: "none") }
        return nil
    }
}

// MARK: - Tier A: LRCLIB exact match

extension LyricsRepositoryImpl {
    private func tierAExactMatch(candidates: [Track], tracing: Bool) async -> TierAttempt {
        var trace: [String] = []
        for c in candidates where !c.artist.isEmpty {
            guard let result = await dataSource.get(title: c.title, artist: c.artist, duration: c.duration) else {
                if tracing { trace.append("tierA \(describe(c)) get -> miss") }
                continue
            }
            // Tier A trusts LRCLIB's own exact match as-is (no local validation).
            if tracing { trace.append("tierA \(describe(c)) get -> \(describe(result)) ACCEPT(unvalidated)") }
            let displayResult = displayAdjusted(result, candidate: c)
            await store(displayResult, track: c)
            return TierAttempt(result: displayResult, trace: trace)
        }
        return TierAttempt(result: nil, trace: trace)
    }
}

// MARK: - Tier B: LRCLIB fuzzy search + validation

extension LyricsRepositoryImpl {
    private func tierBValidatedSearch(candidates: [Track], tracing: Bool) async -> TierAttempt {
        var trace: [String] = []
        for c in candidates {
            let query = c.artist.isEmpty ? c.title : "\(c.title) \(c.artist)"
            guard let responses = await dataSource.search(query: query) else {
                if tracing { trace.append("tierB \(describe(c)) search '\(query)' -> no response") }
                continue
            }
            // LRCLIB fuzzy search can return several lyric-bearing results, only some
            // of which pass validation. Validate every candidate response — not just
            // the first — and accept the first valid one (synced preferred over plain)
            // so a noisy leading result can't sink an otherwise-matching later hit.
            let lyricBearing = responses.filter { $0.syncedLyrics != nil || $0.plainLyrics != nil }
            let valid = lyricBearing.filter { validator.isValid(candidate: c, result: $0) }
            guard let matched = valid.first(where: { $0.syncedLyrics != nil }) ?? valid.first else {
                if tracing { trace.append("tierB \(describe(c)) search '\(query)' -> \(tierBMissReason(c, responses, lyricBearing))") }
                continue
            }
            if tracing { trace.append("tierB \(describe(c)) search '\(query)' -> \(describe(matched)) ACCEPT") }
            let displayResult = displayAdjusted(matched, candidate: c)
            await store(displayResult, track: c)
            return TierAttempt(result: displayResult, trace: trace)
        }
        return TierAttempt(result: nil, trace: trace)
    }
}

// MARK: - Tier C: user-defined custom script

extension LyricsRepositoryImpl {
    private func tierCCustomScript(candidates: [Track], tracing: Bool) async -> TierAttempt {
        var trace: [String] = []
        for c in candidates where !c.artist.isEmpty {
            guard let result = await customScriptDataSource.get(title: c.title, artist: c.artist, duration: c.duration) else {
                if tracing { trace.append("tierC \(describe(c)) script -> miss") }
                continue
            }
            guard validator.isValid(candidate: c, result: result) else {
                if tracing { trace.append("tierC \(describe(c)) script -> \(describe(result)) REJECT [\(rejectReason(c, result))]") }
                continue
            }
            if tracing { trace.append("tierC \(describe(c)) script -> \(describe(result)) ACCEPT") }
            let displayResult = displayAdjusted(result, candidate: c)
            await store(displayResult, track: c)
            return TierAttempt(result: displayResult, trace: trace)
        }
        return TierAttempt(result: nil, trace: trace)
    }
}

// MARK: - Private

extension LyricsRepositoryImpl {
    // Fill title and artist independently: a Tier C script may return a valid
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

// MARK: - Resolution trace (#331)

extension LyricsRepositoryImpl {
    // A tier's outcome plus the trace lines it produced (empty when tracing is off).
    private struct TierAttempt {
        let result: LyricsResult?
        let trace: [String]
    }

    private func flush(_ trace: [String], outcome: String) {
        resolutionLog.record((trace + ["result: \(outcome)"]).joined(separator: "\n"))
    }

    private func traceHeader(_ candidates: [Track]) -> [String] {
        [
            "=== lyrics resolve  candidates=\(candidates.count) ===",
            "candidates: " + candidates.map { describe($0) }.joined(separator: " | "),
        ]
    }

    private func tierBMissReason(_ c: Track, _ responses: [LyricsResult], _ lyricBearing: [LyricsResult]) -> String {
        guard let firstBearing = lyricBearing.first else {
            return "no lyric-bearing result (\(responses.count) responses)"
        }
        return "found \(describe(firstBearing)) REJECT [\(rejectReason(c, firstBearing))]"
    }

    private func describe(_ t: Track) -> String {
        "\(orDash(t.title))/\(orDash(t.artist))/\(durationText(t.duration))"
    }

    private func describe(_ r: LyricsResult) -> String {
        let kind = r.syncedLyrics != nil ? "synced" : (r.plainLyrics != nil ? "plain" : "none")
        return "\(r.trackName ?? "-")/\(r.artistName ?? "-")/\(durationText(r.duration)) [\(kind)]"
    }

    private func rejectReason(_ c: Track, _ r: LyricsResult) -> String {
        let sim = validator.titleSimilarity(candidate: c, result: r).map { String(format: "titleSim=%.2f", $0) } ?? "titleSim=n/a"
        let dur = validator.durationDelta(candidate: c, result: r).map { String(format: "durΔ=%.0fs", $0) } ?? "durΔ=n/a"
        return "\(sim) \(dur)"
    }

    private func orDash(_ s: String) -> String { s.isEmpty ? "-" : s }

    private func durationText(_ d: Double?) -> String {
        d.map { String(format: "%.0fs", $0) } ?? "-"
    }
}
