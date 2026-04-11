import Domain
import Foundation
import Testing

@testable import MetadataDataSource

@Suite("MusicBrainzMetadataDataSourceImpl")
struct MusicBrainzMetadataDataSourceImplTests {
    @Test("matchRecordings skips entries without artist and deduplicates title variants")
    func matchRecordingsDeduplicates() {
        let sut = MusicBrainzMetadataDataSourceImpl { _ in nil }
        let regex = RegexMetadataDataSourceImpl()
        let response = MusicBrainzResponse(recordings: [
            MusicBrainzRecording(
                id: "1",
                title: "Brave Shine",
                length: 225000,
                artistCredit: [ArtistCredit(name: "Aimer")]
            ),
            MusicBrainzRecording(
                id: "2",
                title: "No Artist",
                length: nil,
                artistCredit: nil
            ),
            MusicBrainzRecording(
                id: "3",
                title: "Aimer『Brave Shine』",
                length: 225000,
                artistCredit: [ArtistCredit(name: "Aimer")]
            ),
        ])

        let result = sut.matchRecordings(from: response, regex: regex)

        let hasCanonical = result.contains { metadata in
            metadata.title == "Brave Shine" && metadata.artist == "Aimer" && metadata.musicbrainzId == "1"
        }
        let hasBracketed = result.contains { metadata in
            metadata.title == "Aimer『Brave Shine』" && metadata.musicbrainzId == "3"
        }
        let hasMissingArtist = result.contains { metadata in
            metadata.musicbrainzId == "2"
        }
        let uniqueKeys = Set(result.map { "\($0.musicbrainzId)|\($0.artist)|\($0.title)" })
        #expect(hasCanonical)
        #expect(hasBracketed)
        #expect(!hasMissingArtist)
        #expect(uniqueKeys.count == result.count)
    }

    @Test("resolve returns matches from the first successful query")
    func resolveUsesFirstSuccessfulQuery() async {
        let calls = LockedCalls()
        let sut = MusicBrainzMetadataDataSourceImpl { api in
            await calls.append(api)
            return MusicBrainzResponse(recordings: [
                MusicBrainzRecording(
                    id: "mbid-1",
                    title: "Brave Shine",
                    length: 225000,
                    artistCredit: [ArtistCredit(name: "Aimer")]
                )
            ])
        }

        let result = await sut.resolve(track: Track(title: "Aimer - Brave Shine", artist: "Uploader"))

        let queries = await calls.values
        #expect(result.count >= 1)
        #expect(result.first?.title == "Brave Shine")
        #expect(result.first?.artist == "Aimer")
        guard queries.count == 1 else {
            Issue.record("Expected exactly one query, got \(queries.count)")
            return
        }
        guard case .searchRecording(let title, let artist, let duration) = queries[0] else {
            Issue.record("Expected searchRecording query")
            return
        }
        #expect(title == "Brave Shine")
        #expect(artist == "Aimer")
        #expect(duration == nil)
    }

    @Test("resolve falls back to artistless query when first query has no candidates")
    func resolveFallsBackToSecondQuery() async {
        let calls = LockedCalls()
        let sut = MusicBrainzMetadataDataSourceImpl { api in
            await calls.append(api)
            let index = await calls.count
            if index == 1 {
                return MusicBrainzResponse(recordings: [])
            }
            return MusicBrainzResponse(recordings: [
                MusicBrainzRecording(
                    id: "mbid-2",
                    title: "Brave Shine",
                    length: 225000,
                    artistCredit: [ArtistCredit(name: "Aimer")]
                )
            ])
        }

        let result = await sut.resolve(track: Track(title: "Brave Shine", artist: "Unknown"))

        let queries = await calls.values
        #expect(result.count >= 1)
        guard queries.count == 2 else {
            Issue.record("Expected exactly two queries, got \(queries.count)")
            return
        }
        guard case .searchRecording(_, let firstArtist, _) = queries[0],
            case .searchRecording(_, let secondArtist, _) = queries[1]
        else {
            Issue.record("Expected searchRecording queries")
            return
        }
        #expect(firstArtist == "Unknown")
        #expect(secondArtist == nil)
    }

    @Test("resolve returns empty when all lookups fail")
    func resolveReturnsEmpty() async {
        let sut = MusicBrainzMetadataDataSourceImpl { _ in nil }

        let result = await sut.resolve(track: Track(title: "Missing Song", artist: "Missing Artist"))

        #expect(result.isEmpty)
    }
}

private actor LockedCalls {
    private var storage: [MusicBrainzAPI] = []

    func append(_ value: MusicBrainzAPI) {
        storage.append(value)
    }

    var values: [MusicBrainzAPI] { storage }
    var count: Int { storage.count }
}
