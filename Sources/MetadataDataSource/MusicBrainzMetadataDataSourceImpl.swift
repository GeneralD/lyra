import Domain
import Foundation
@preconcurrency import Papyrus

public struct MusicBrainzMetadataDataSourceImpl {
    private let apiFactory: () -> any MusicBrainz

    public init() {
        self.init { EphemeralSessionMusicBrainz() }
    }

    init(api: any MusicBrainz) {
        self.init { api }
    }

    init(apiFactory: @escaping () -> any MusicBrainz) {
        self.apiFactory = apiFactory
    }
}

// Safe: `apiFactory` is set at init and never mutated; it only constructs a fresh,
// call-local API client (or returns the injected test stub).
extension MusicBrainzMetadataDataSourceImpl: @unchecked Sendable {}

extension MusicBrainzMetadataDataSourceImpl: MetadataDataSource {
    public func resolve(track: Track) async -> [MusicBrainzMetadata] {
        let regex = RegexMetadataDataSourceImpl()
        let parsed = regex.parseArtistTitle(track.title)
        let normalized = parsed.title
        let normalizedArtist = regex.normalizeArtist(parsed.artist ?? track.artist)

        for (title, artist) in [(normalized, normalizedArtist), (normalized, nil as String?)] {
            let query = MusicBrainzAPI.luceneQuery(title: title, artist: artist, duration: nil)
            do {
                let response = try await apiFactory().searchRecording(query: query, fmt: "json", limit: 5)
                let candidates = matchRecordings(from: response, regex: regex)
                guard !candidates.isEmpty else { continue }
                return candidates
            } catch {
                fputs("lyra: MusicBrainz search failed: \(error)\n", stderr)
            }
        }

        return []
    }
}

extension MusicBrainzMetadataDataSourceImpl {
    func matchRecordings(from response: MusicBrainzResponse, regex: RegexMetadataDataSourceImpl) -> [MusicBrainzMetadata] {
        response.recordings.flatMap { recording -> [MusicBrainzMetadata] in
            guard let artistName = recording.artistName else { return [] }
            var seen = Set<String>()
            return [recording.title, regex.normalize(recording.title), regex.stripBrackets(recording.title)]
                .filter { seen.insert($0).inserted }
                .map { title in
                    MusicBrainzMetadata(
                        title: title, artist: artistName,
                        duration: recording.duration, musicbrainzId: recording.id
                    )
                }
        }
    }
}
