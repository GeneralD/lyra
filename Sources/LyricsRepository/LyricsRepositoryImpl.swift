import Dependencies
import Domain
import Foundation

public struct LyricsRepositoryImpl {
    @Dependency(\.lyricsCache) private var cache
    @Dependency(\.lyricsDataSource) private var dataSource
    @Dependency(\.customScriptLyricsDataSource) private var customScriptDataSource
    @Dependency(\.lyricsResolutionLog) private var resolutionLog
    private let validator = LyricsMatchValidator()
    private let titleReader = SongTitleReader()

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

        // Screen and normalize once, up front. The normalized title is the search key, the
        // validation subject, and the cache identity all at once — deriving it separately
        // per tier would let the three drift apart, and a title rewritten only for the
        // query gets re-validated against its raw form and thrown away (#343).
        let screened = screen(candidates)
        let readable = screened.map(\.track)
        // Candidates no lyrics catalog could hold are kept out of the LRCLIB tiers but
        // still offered to Tier C, whose user script may index things LRCLIB does not.
        let searchable = screened.filter { $0.notASongReason == nil }.map(\.track)

        var trace = tracing ? traceHeader(readable) + screeningTrace(screened) : []

        for candidate in readable {
            guard let cached = await cache.read(title: candidate.title, artist: candidate.artist) else { continue }
            // Rows written before validation existed (pre-#308 upgrades) can hold lyrics
            // that never matched this candidate — a poisoned entry that would otherwise
            // short-circuit the validated tiers forever. Re-validate on read; an invalid
            // entry is skipped so Tier A/B/C can overwrite it with a real match.
            // Through `accepted` like every tier, not returned raw: rows written before the
            // timing-trust rule existed can validate under the relaxed duration tolerance
            // while running far enough off to scroll out of step, and a cache hit that
            // skipped the demotion would serve those drifting timings forever (#344 review).
            if validator.isValid(candidate: candidate, result: cached) {
                if tracing {
                    trace.append("cache HIT  \(describe(candidate)) -> \(describe(cached))")
                    flush(trace, outcome: "cache")
                }
                return accepted(cached, candidate: candidate)
            }
            if tracing {
                trace.append(
                    "cache REJECT \(describe(candidate)) -> \(describe(cached))  [\(rejectReason(candidate, cached))]")
            }
        }

        let a = await tierAExactMatch(candidates: searchable, tracing: tracing)
        trace += a.trace
        if let result = a.result {
            if tracing { flush(trace, outcome: "tierA") }
            return result
        }

        let b = await tierBValidatedSearch(candidates: searchable, tracing: tracing)
        trace += b.trace
        if let result = b.result {
            if tracing { flush(trace, outcome: "tierB") }
            return result
        }

        let c = await tierCCustomScript(candidates: readable, tracing: tracing)
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
                accepted(result, candidate: c),
                tracing ? ["tierA \(describe(c)) get -> \(describe(result)) ACCEPT"] : []
            )
        }
    }
}

// MARK: - Tier B: LRCLIB fuzzy search + validation

extension LyricsRepositoryImpl {
    private func tierBValidatedSearch(candidates: [Track], tracing: Bool) async -> TierAttempt {
        await attempt(over: candidates) { c in
            let structured = await probeSearch(c, using: .structured, tracing: tracing)
            // An artist-agreeing hit from the precise index is the strongest evidence
            // either index can offer; nothing the free-text one returns would outrank it,
            // so stop here and skip the second request.
            if let hit = structured.match, validator.artistAgrees(candidate: c, result: hit) {
                return .hit(accepted(hit, candidate: c), structured.trace + acceptTrace(c, hit, tracing))
            }
            // Otherwise the free-text index still gets its turn. Deciding the fallback on
            // an *empty* structured array was the hole (#344 review): rows that all fail
            // validation — or that match the title while naming a different performer —
            // are precisely the disagreement the second index exists to resolve, so
            // stopping at "the array was non-empty" lost exactly those cases.
            let free = await probeSearch(c, using: .freeText, tracing: tracing)
            guard let best = arbitrated(structured.match, free.match, candidate: c) else {
                return .miss(structured.trace + free.trace)
            }
            return .hit(accepted(best, candidate: c), structured.trace + free.trace + acceptTrace(c, best, tracing))
        }
    }

    // LRCLIB's two search indexes, which disagree in both directions.
    private enum SearchIndex { case structured, freeText }

    // One index's answer: the best result that survived validation (nil when none did),
    // plus the trace lines describing what was asked and what came back.
    private struct SearchProbe {
        let match: LyricsResult?
        let trace: [String]
    }

    private func probeSearch(_ c: Track, using index: SearchIndex, tracing: Bool) async -> SearchProbe {
        let asked = await search(c, using: index)
        guard let responses = asked.responses else {
            return SearchProbe(match: nil, trace: tracing ? ["tierB \(describe(c)) \(asked.form) -> no response"] : [])
        }
        // LRCLIB fuzzy search can return several lyric-bearing results, only some of
        // which pass validation. Validate every response — not just the first — so a
        // noisy leading result can't sink an otherwise-matching later hit.
        let lyricBearing = responses.filter { $0.syncedLyrics != nil || $0.plainLyrics != nil }
        let valid = lyricBearing.filter { validator.isValid(candidate: c, result: $0) }
        guard let matched = preferred(among: valid, candidate: c) else {
            return SearchProbe(
                match: nil,
                trace: tracing
                    ? ["tierB \(describe(c)) \(asked.form) -> \(tierBMissReason(c, responses, lyricBearing))"] : [])
        }
        return SearchProbe(
            match: matched,
            trace: tracing ? ["tierB \(describe(c)) \(asked.form) -> \(describe(matched)) valid"] : [])
    }

    // `track_name=` ranks clean catalog titles first — the free-text form answers `白日`
    // with `King Gnu - 白日`, whose title the validator then fails on similarity — but it
    // is also the narrower index: measured over the trace log's response-bearing
    // candidates, 10 of 40 came back empty from `track_name=` while `q=` still found them
    // (`TIGER&DRAGON` among them). So ask the precise index first and fall back (#343).
    //
    // The artist is never sent to either. As a server-side filter it is a hard cut on a
    // field that is routinely a channel name or a cover credit, and agreement is checked
    // locally afterwards anyway — sending it returned nothing at all across a
    // 45-candidate sample.
    private func search(_ c: Track, using index: SearchIndex) async -> (responses: [LyricsResult]?, form: String) {
        guard index == .structured else {
            let query = c.artist.isEmpty ? c.title : "\(c.title) \(c.artist)"
            return (await dataSource.search(query: query), "search q='\(query)'")
        }
        return (await dataSource.search(trackName: c.title), "search track_name='\(c.title)'")
    }

    // The structured query named no artist, so its answer can be a same-titled song by
    // another performer that validated on title and a ±5 s duration alone. When the
    // free-text answer — whose query *did* carry the artist — agrees on the performer, it
    // wins; failing that the precise index's answer stands, since requiring agreement
    // outright would discard the uploads whose artist is a channel name (#342).
    private func arbitrated(_ structured: LyricsResult?, _ free: LyricsResult?, candidate: Track) -> LyricsResult? {
        guard let free else { return structured }
        guard validator.artistAgrees(candidate: candidate, result: free) else { return structured ?? free }
        return free
    }

    private func acceptTrace(_ c: Track, _ result: LyricsResult, _ tracing: Bool) -> [String] {
        tracing ? ["tierB \(describe(c)) -> \(describe(result)) ACCEPT"] : []
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
                accepted(result, candidate: c),
                tracing ? ["tierC \(describe(c)) script -> \(describe(result)) ACCEPT"] : []
            )
        }
    }
}

// MARK: - Candidate screening (#343)

extension LyricsRepositoryImpl {
    // A candidate as the tiers should see it: the title normalized for searching, plus
    // why — if at all — no lyrics catalog could hold it.
    private struct ScreenedCandidate {
        let original: Track
        let track: Track
        let notASongReason: String?
    }

    private func screen(_ candidates: [Track]) -> [ScreenedCandidate] {
        candidates.map { candidate in
            switch titleReader.read(candidate) {
            case .song(let title):
                return ScreenedCandidate(
                    original: candidate, track: candidate.withTitle(title), notASongReason: nil)
            case .notASong(let reason):
                return ScreenedCandidate(original: candidate, track: candidate, notASongReason: reason)
            }
        }
    }

    // Screening decisions are traced once, up front, rather than per tier: they are a
    // property of the candidate, not of any one tier, and repeating them three times
    // would bury the tier lines that actually explain a resolution.
    private func screeningTrace(_ screened: [ScreenedCandidate]) -> [String] {
        screened.compactMap { c in
            if let reason = c.notASongReason {
                return "screen \(describe(c.original)) -> not a song [\(reason)]"
            }
            guard c.track.title != c.original.title else { return nil }
            return "screen \(describe(c.original)) -> title '\(c.track.title)'"
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

    // The single form every tier hands a validated result back in: display identity
    // filled in from the candidate, timings kept only when they can be trusted. Tiers
    // adjusting results their own way is how #326's cache poisoning happened, so there
    // is one path and all three take it.
    private func accepted(_ result: LyricsResult, candidate: Track) -> LyricsResult {
        let displayed = displayAdjusted(result, candidate: candidate)
        guard syncedIsTrustworthy(candidate: candidate, result: result) else {
            return displayed.withoutSyncedLyrics()
        }
        return displayed
    }

    // Prefer a result whose timings can be trusted; failing that, take the best available
    // and hand it back as plain text. A cover legitimately clears validation on the
    // relaxed duration tolerance (#326) while running well off the original's length, and
    // the original's synced copy would then scroll out of step with what is playing.
    private func preferred(among valid: [LyricsResult], candidate: Track) -> LyricsResult? {
        let trusted = valid.first {
            $0.syncedLyrics != nil && syncedIsTrustworthy(candidate: candidate, result: $0)
        }
        guard trusted == nil else { return trusted }
        return valid.first { $0.plainLyrics != nil } ?? valid.first
    }

    // Only a *known* gap demotes. An unread duration is absent evidence, not evidence of
    // drift — a media source that cannot report a length sends 0, and treating that as a
    // mismatch would strip the timings off exactly the plays #326 restored.
    private func syncedIsTrustworthy(candidate: Track, result: LyricsResult) -> Bool {
        guard let delta = validator.durationDelta(candidate: candidate, result: result) else { return true }
        return delta <= validator.durationToleranceSeconds
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
