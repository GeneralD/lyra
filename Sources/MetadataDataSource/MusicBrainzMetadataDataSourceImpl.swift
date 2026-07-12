import Domain
import Foundation
@preconcurrency import Papyrus
import ScopedAPISession

public struct MusicBrainzMetadataDataSourceImpl {
    private let apiSession: ScopedAPISession<any MusicBrainz>

    public init() {
        self.init(
            apiSession: ScopedAPISession(timeout: 10) {
                MusicBrainzAPI(provider: Provider(baseURL: MusicBrainzAPI.baseURL, urlSession: $0))
            }
        )
    }

    init(api: any MusicBrainz) {
        self.init(apiSession: ScopedAPISession(timeout: 10) { _ in api })
    }

    init(apiSession: ScopedAPISession<any MusicBrainz>) {
        self.apiSession = apiSession
    }
}

extension MusicBrainzMetadataDataSourceImpl: Sendable {}

extension MusicBrainzMetadataDataSourceImpl: MetadataDataSource {
    public func resolve(track: Track) async -> [MusicBrainzMetadata] {
        let regex = RegexMetadataDataSourceImpl()
        let parsed = regex.parseArtistTitle(track.title)
        let normalized = parsed.title
        let normalizedArtist = regex.normalizeArtist(parsed.artist ?? track.artist)

        for (title, artist) in [(normalized, normalizedArtist), (normalized, nil as String?)] {
            let query = MusicBrainzAPI.luceneQuery(title: title, artist: artist, duration: nil)
            do {
                let response = try await apiSession.withAPI { try await $0.searchRecording(query: query, fmt: "json", limit: 5) }
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
