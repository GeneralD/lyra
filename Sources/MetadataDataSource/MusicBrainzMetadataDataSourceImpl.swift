import Alamofire
import CollectionKit
import Dependencies
import Domain
import Foundation

public struct MusicBrainzMetadataDataSourceImpl {
    @Dependency(\.metadataCache) private var metadataCache

    public init() {}
}

extension MusicBrainzMetadataDataSourceImpl: Sendable {}

extension MusicBrainzMetadataDataSourceImpl: MetadataDataSource {
    public func resolve(track: Track) async -> [Track] {
        let regexCandidates = generateCandidates(title: track.title, artist: track.artist)
        let musicBrainzCandidates = await fetchMusicBrainzCandidates(title: track.title, artist: track.artist, duration: nil)

        var seen = Set<String>()
        return (musicBrainzCandidates + regexCandidates)
            .filter { seen.insert("\($0.title.lowercased())|\($0.artist.lowercased())").inserted }
    }
}

// MARK: - MusicBrainz refinement

private extension MusicBrainzMetadataDataSourceImpl {
    func fetchMusicBrainzCandidates(title: String, artist: String, duration: TimeInterval?) async -> [Track] {
        let parsed = parseArtistTitle(title)
        let normalized = parsed.title
        let normalizedArtist = normalizeArtist(parsed.artist ?? artist)

        if let cached = await metadataCache.read(title: normalized, artist: normalizedArtist) {
            return [Track(title: cached.title, artist: cached.artist)]
        }

        for query: MusicBrainzAPI in [
            .searchRecording(title: normalized, artist: normalizedArtist, duration: duration),
            .searchRecording(title: normalized, artist: nil, duration: nil),
        ] {
            guard let response: MusicBrainzResponse = await musicbrainz(query) else { continue }
            let candidates = matchRecordings(from: response, cacheKey: (normalized, normalizedArtist))
            guard !candidates.isEmpty else { continue }
            return candidates
        }

        return []
    }

    func matchRecordings(from response: MusicBrainzResponse, cacheKey: (title: String, artist: String)) -> [Track] {
        var candidates: [Track] = []
        for recording in response.recordings {
            guard let artistName = recording.artistName else { continue }
            var seen = Set<String>()
            let titles = [recording.title, normalize(recording.title), stripBrackets(recording.title)]
                .filter { seen.insert($0).inserted }
            for t in titles {
                candidates.append(Track(title: t, artist: artistName))
            }
            // Cache the first recording's metadata for future lookups
            if candidates.count == titles.count {
                let metadata = MusicBrainzMetadata(
                    title: recording.title, artist: artistName,
                    duration: recording.duration, musicbrainzId: recording.id
                )
                Task { [metadataCache] in
                    try? await metadataCache.write(queryTitle: cacheKey.title, queryArtist: cacheKey.artist, metadata: metadata)
                }
            }
        }
        return candidates
    }

    func musicbrainz<T: Decodable & Sendable>(_ api: MusicBrainzAPI) async -> T? {
        await AF.request(api)
            .validate(statusCode: 200 ..< 300)
            .serializingDecodable(T.self)
            .response.value
    }
}

// MARK: - Noise patterns

/// Bracket-like patterns to strip entirely (noise brackets)
private let bracketPatterns = [
    "【[^】]*】",
    "\\([^)]*\\)", "（[^）]*）", "\\[[^\\]]*\\]",
]


/// Content-aware bracket patterns (case-insensitive) — strip brackets containing these
private let noiseBracketPatterns = [
    #"\(.*?(?:official|audio|video|lyrics|visualizer|music\s*video).*?\)"#,
    #"\(.*?(?:live|remaster(?:ed)?|acoustic|instrumental|piano\s*ver|full\s*ver|short\s*ver|cover).*?\)"#,
    #"\(.*?(?:\d{4}\s*remaster).*?\)"#,
    #"（.*?(?:official|live|remaster).*?）"#,
    #"\[.*?\]"#,
]

/// Suffix patterns after hyphen to strip (case-insensitive)
private let suffixPatterns = [
    #"\s*-\s*(?:official|audio|video|lyrics)\s*$"#,
    #"\s*-\s*(?:live|remaster(?:ed)?)\s*.*$"#,
    #"\s*-\s*\d{4}\s*remaster.*$"#,
]

/// Words that indicate a segment is noise
private let noiseWords: Set<String> = [
    "mv", "pv", "official video", "official music video", "music video",
    "lyric video", "lyrics video", "the first take", "audio", "official audio",
    "full ver.", "full version", "short ver.", "short version", "topic", "vevo",
    "hd", "4k", "visualizer", "official", "shorts",
]

/// Artist name suffixes to strip
private let artistSuffixPatterns = [
    #"\s*-\s*Topic$"#,
    #"\s*VEVO$"#,
    #"\s*Official\s*Channel$"#,
    #"\s*Official$"#,
]

// MARK: - Public API

extension MusicBrainzMetadataDataSourceImpl {
    /// Normalize a title by removing noise brackets, suffixes, and series markers
    public func normalize(_ title: String) -> String {
        var s = title

        // Remove everything after / (channel/series name like "THE FIRST TAKE")
        if let slashRange = s.range(of: " / ") {
            s = String(s[..<slashRange.lowerBound])
        }

        // Remove content-aware noise brackets
        for pattern in noiseBracketPatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        // Remove noise suffixes after hyphen
        for pattern in suffixPatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        // Collapse whitespace
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Normalize an artist name by removing platform suffixes
    public func normalizeArtist(_ artist: String) -> String {
        artistSuffixPatterns.reduce(artist) {
            $0.replacingOccurrences(of: $1, with: "", options: [.regularExpression, .caseInsensitive])
        }
        .trimmingCharacters(in: .whitespaces)
    }

    /// Strip all bracket content (aggressive — for fallback searches)
    public func stripBrackets(_ s: String) -> String {
        bracketPatterns
            .reduce(s) { $0.replacingOccurrences(of: $1, with: "", options: .regularExpression) }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Parse artist and title from common formats:
    /// - `Artist「Title」-suffix-`
    /// - `Artist『Title』`
    /// - `Artist - Title (noise)`
    public func parseArtistTitle(_ raw: String) -> (artist: String?, title: String) {
        let normalized = normalize(raw)

        // Try Japanese quote brackets: Artist「Title」
        if let match = normalized.firstMatch(of: /「([^」]+)」|『([^』]+)』/) {
            let title = (match.output.1 ?? match.output.2)
                .map(String.init) ?? normalized
            let artist = normalized[..<match.range.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            return (artist.isEmpty ? nil : artist, title)
        }

        // Try "Artist - Title"
        guard let dashRange = normalized.range(of: " - ") else {
            return (nil, normalized)
        }
        let artist = String(normalized[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let title = String(normalized[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (artist, title)
    }

    public func isNoise(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return noiseWords.contains(trimmed.lowercased())
    }

    public func splitTitle(_ title: String) -> [String] {
        [" - ", " / ", " | ", "｜"]
            .reduce([title]) { parts, sep in parts.flatMap { $0.components(separatedBy: sep) } }
            .map { stripBrackets($0).trimmingCharacters(in: .whitespaces) }
            .unless(isNoise)
    }

    public func generateCandidates(title: String, artist: String) -> [Track] {
        let normalizedArtist = normalizeArtist(artist)
        let parsed = parseArtistTitle(title)
        let normalized = normalize(title)
        let stripped = stripBrackets(title)
        let parts = splitTitle(title)
        let artistUsable = !isNoise(normalizedArtist)

        var seen = Set<String>()
        return [
            // From parseArtistTitle (best for "Artist - Title" format)
            parsed.artist.map { [Track(title: parsed.title, artist: $0)] } ?? [],
            // Normalized title with MediaRemote artist
            artistUsable ? [Track(title: normalized, artist: normalizedArtist)] : [],
            // Stripped title with artist
            artistUsable ? [Track(title: stripped, artist: normalizedArtist)] : [],
            // Split parts as artist-title pairs
            parts.count >= 2
                ? [Track(title: parts[1], artist: parts[0]),
                   Track(title: parts[0], artist: parts[1])]
                : [],
            // Individual parts with artist
            artistUsable
                ? parts.unless { $0 == stripped }.map { Track(title: $0, artist: normalizedArtist) }
                : [],
            // Title only (last resort)
            parts.count == 1 && !artistUsable
                ? [Track(title: parts[0], artist: "")]
                : [],
        ]
        .flatten
        .filter { seen.insert("\($0.title.lowercased())|\($0.artist.lowercased())").inserted }
    }
}
