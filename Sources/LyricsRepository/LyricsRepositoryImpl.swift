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

// MARK: - Candidate probing

extension LyricsRepositoryImpl {
    // What probing one candidate produced: the lyrics it accepted (nil on a miss or a
    // rejection) plus the trace lines it wants recorded (empty when the debug log is off).
    private struct ProbeOutcome: Sendable {
        let result: LyricsResult?
        let trace: [String]

        static func miss(_ trace: [String]) -> Self { Self(result: nil, trace: trace) }
        static func hit(_ result: LyricsResult, _ trace: [String]) -> Self { Self(result: result, trace: trace) }
    }

    // How many candidates a tier probes concurrently. Deliberately small: the sources are
    // free community APIs and a user-supplied script, and a 17-candidate track (the
    // observed maximum) firing 17 requests at once is a burst none of them asked for.
    private static let waveSize = 4

    // Candidates arrive in confidence order (LLM > MusicBrainz > Regex > raw) and the
    // serial loop this replaces walked them one network round-trip at a time, so a track
    // with N candidates cost N × the 10s timeout *per tier* — the "lyrics only show up
    // halfway through the song" complaint in #326. The trace log measured N at up to 17.
    //
    // Probing all of them at once would fix the latency but lose the ordering. Instead,
    // probe in waves: concurrent *within* a wave, sequential *across* waves, taking the
    // highest-priority hit of the first wave that yields one. Every candidate in a wave
    // outranks every candidate in the next, so the result is exactly what the serial loop
    // picked — reached in ceil(N / waveSize) round-trips instead of N.
    private func attempt(
        over candidates: [Track],
        probe: @escaping @Sendable (Track) async -> ProbeOutcome
    ) async -> TierAttempt {
        guard !candidates.isEmpty else { return TierAttempt(result: nil, trace: []) }

        let wave = Array(candidates.prefix(Self.waveSize))
        let settled = await withTaskGroup(of: (offset: Int, outcome: ProbeOutcome).self) { group in
            for (offset, candidate) in wave.enumerated() {
                group.addTask { (offset, await probe(candidate)) }
            }
            // Probes finish out of order, so outcomes are keyed by offset rather than by
            // arrival. The accumulator is mutable because the wave can be abandoned
            // mid-flight by the early exit below.
            var byOffset: [Int: ProbeOutcome] = [:]
            for await (offset, outcome) in group {
                byOffset[offset] = outcome
                // A hit is only final once every higher-priority offset has reported a
                // miss — until then one of them could still outrank it. Once it is final,
                // whatever is still in flight can only produce losers, so cancel rather
                // than pay their timeouts: waiting for them would hand back, as latency,
                // exactly the early return the serial loop used to get for free.
                guard Self.isSettled(byOffset, waveSize: wave.count) else { continue }
                group.cancelAll()
                break
            }
            return byOffset
        }

        // Re-keyed into candidate order, so the trace reads the same way regardless of
        // which request happened to come back first.
        let reported = wave.indices.compactMap { offset in settled[offset].map { (offset: offset, outcome: $0) } }
        let trace = reported.flatMap(\.outcome.trace)

        guard let hit = reported.first(where: { $0.outcome.result != nil }), let result = hit.outcome.result else {
            let rest = await attempt(over: Array(candidates.dropFirst(Self.waveSize)), probe: probe)
            return TierAttempt(result: rest.result, trace: trace + rest.trace)
        }
        await store(result, track: wave[hit.offset])
        return TierAttempt(result: result, trace: trace)
    }

    // Settled once the contiguous run of reported offsets contains a hit — nothing still
    // unreported outranks it — or once every offset in the wave has reported.
    private static func isSettled(_ byOffset: [Int: ProbeOutcome], waveSize: Int) -> Bool {
        let reported = (0..<waveSize).prefix { byOffset[$0] != nil }
        return reported.count == waveSize || reported.contains { byOffset[$0]?.result != nil }
    }
}

// MARK: - Tier A: LRCLIB exact match

extension LyricsRepositoryImpl {
    private func tierAExactMatch(candidates: [Track], tracing: Bool) async -> TierAttempt {
        await attempt(over: candidates.filter { !$0.artist.isEmpty }) { c in
            guard let result = await dataSource.get(title: c.title, artist: c.artist, duration: c.duration) else {
                return .miss(tracing ? ["tierA \(describe(c)) get -> miss"] : [])
            }
            // Validate before caching, symmetric with Tier B/C. LRCLIB's /api/get does its
            // own loose matching and can return a different song; caching that unvalidated
            // used to poison the entry so the read-side re-validation discarded it forever,
            // forcing a live re-fetch on every replay (#326). A validated write is stable.
            guard validator.isValid(candidate: c, result: result) else {
                return .miss(
                    tracing ? ["tierA \(describe(c)) get -> \(describe(result)) REJECT [\(rejectReason(c, result))]"] : [])
            }
            return .hit(
                displayAdjusted(result, candidate: c),
                tracing ? ["tierA \(describe(c)) get -> \(describe(result)) ACCEPT"] : []
            )
        }
    }
}

// MARK: - Tier B: LRCLIB fuzzy search + validation

extension LyricsRepositoryImpl {
    private func tierBValidatedSearch(candidates: [Track], tracing: Bool) async -> TierAttempt {
        await attempt(over: candidates) { c in
            let query = c.artist.isEmpty ? c.title : "\(c.title) \(c.artist)"
            guard let responses = await dataSource.search(query: query) else {
                return .miss(tracing ? ["tierB \(describe(c)) search '\(query)' -> no response"] : [])
            }
            // LRCLIB fuzzy search can return several lyric-bearing results, only some
            // of which pass validation. Validate every candidate response — not just
            // the first — and accept the first valid one (synced preferred over plain)
            // so a noisy leading result can't sink an otherwise-matching later hit.
            let lyricBearing = responses.filter { $0.syncedLyrics != nil || $0.plainLyrics != nil }
            let valid = lyricBearing.filter { validator.isValid(candidate: c, result: $0) }
            guard let matched = valid.first(where: { $0.syncedLyrics != nil }) ?? valid.first else {
                return .miss(
                    tracing ? ["tierB \(describe(c)) search '\(query)' -> \(tierBMissReason(c, responses, lyricBearing))"] : [])
            }
            return .hit(
                displayAdjusted(matched, candidate: c),
                tracing ? ["tierB \(describe(c)) search '\(query)' -> \(describe(matched)) ACCEPT"] : []
            )
        }
    }
}

// MARK: - Tier C: user-defined custom script

extension LyricsRepositoryImpl {
    private func tierCCustomScript(candidates: [Track], tracing: Bool) async -> TierAttempt {
        await attempt(over: candidates.filter { !$0.artist.isEmpty }) { c in
            guard let result = await customScriptDataSource.get(title: c.title, artist: c.artist, duration: c.duration) else {
                return .miss(tracing ? ["tierC \(describe(c)) script -> miss"] : [])
            }
            guard validator.isValid(candidate: c, result: result) else {
                return .miss(
                    tracing ? ["tierC \(describe(c)) script -> \(describe(result)) REJECT [\(rejectReason(c, result))]"] : [])
            }
            return .hit(
                displayAdjusted(result, candidate: c),
                tracing ? ["tierC \(describe(c)) script -> \(describe(result)) ACCEPT"] : []
            )
        }
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
