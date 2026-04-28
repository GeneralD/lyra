import Domain
import Foundation
import Testing

@testable import MetadataDataSource

@Suite("MusicBrainzMetadataDataSourceImpl")
struct MusicBrainzMetadataDataSourceImplTests {
    @Test("default init() wires the Papyrus-generated MusicBrainzAPI")
    func defaultInitInstantiates() {
        _ = MusicBrainzMetadataDataSourceImpl()
    }

    @Test("matchRecordings skips entries without artist and deduplicates title variants")
    func matchRecordingsDeduplicates() {
        let sut = MusicBrainzMetadataDataSourceImpl(api: MusicBrainzStub())
        let regex = RegexMetadataDataSourceImpl()
        let response = MusicBrainzResponse(recordings: [
            MusicBrainzRecording(
                id: "1",
                title: "Brave Shine",
                length: 225000,
                artistCredit: [ArtistCredit(name: "Aimer")]
            ),
            MusicBrainzRecording(id: "2", title: "No Artist", length: nil, artistCredit: nil),
            MusicBrainzRecording(
                id: "3",
                title: "Aimer『Brave Shine』",
                length: 225000,
                artistCredit: [ArtistCredit(name: "Aimer")]
            ),
        ])

        let result = sut.matchRecordings(from: response, regex: regex)

        #expect(result.contains { $0.title == "Brave Shine" && $0.artist == "Aimer" && $0.musicbrainzId == "1" })
        #expect(result.contains { $0.title == "Aimer『Brave Shine』" && $0.musicbrainzId == "3" })
        #expect(!result.contains { $0.musicbrainzId == "2" })
        #expect(Set(result.map { "\($0.musicbrainzId)|\($0.artist)|\($0.title)" }).count == result.count)
    }

    @Test("resolve returns matches from the first successful query")
    func resolveUsesFirstSuccessfulQuery() async {
        let calls = QueryRecorder()
        let sut = MusicBrainzMetadataDataSourceImpl(
            api: MusicBrainzStub { query, _, _ in
                await calls.append(query)
                return MusicBrainzResponse(recordings: [
                    MusicBrainzRecording(id: "mbid-1", title: "Brave Shine", length: 225000, artistCredit: [ArtistCredit(name: "Aimer")])
                ])
            })

        let result = await sut.resolve(track: Track(title: "Aimer - Brave Shine", artist: "Uploader"))
        let queries = await calls.values

        #expect(result.first?.title == "Brave Shine")
        #expect(result.first?.artist == "Aimer")
        #expect(queries.count == 1)
        #expect(queries.first?.contains("\"Brave Shine\"") == true)
        #expect(queries.first?.contains("artist:\"Aimer\"") == true)
    }

    @Test("resolve falls back to artistless query when first query has no candidates")
    func resolveFallsBackToSecondQuery() async {
        let calls = QueryRecorder()
        let sut = MusicBrainzMetadataDataSourceImpl(
            api: MusicBrainzStub { query, _, _ in
                await calls.append(query)
                let count = await calls.count
                if count == 1 { return MusicBrainzResponse(recordings: []) }
                return MusicBrainzResponse(recordings: [
                    MusicBrainzRecording(id: "mbid-2", title: "Brave Shine", length: 225000, artistCredit: [ArtistCredit(name: "Aimer")])
                ])
            })

        let result = await sut.resolve(track: Track(title: "Brave Shine", artist: "Unknown"))
        let queries = await calls.values

        #expect(!result.isEmpty)
        #expect(queries.count == 2)
        #expect(queries.first?.contains("artist:") == true)
        #expect(queries.last?.contains("artist:") == false)
    }

    @Test("resolve falls back when first query returns only artistless recordings")
    func resolveFallsBackOnArtistlessRecordings() async {
        let calls = QueryRecorder()
        let sut = MusicBrainzMetadataDataSourceImpl(
            api: MusicBrainzStub { query, _, _ in
                await calls.append(query)
                let count = await calls.count
                if count == 1 {
                    return MusicBrainzResponse(recordings: [
                        MusicBrainzRecording(id: "1", title: "Song", length: nil, artistCredit: [])
                    ])
                }
                return MusicBrainzResponse(recordings: [
                    MusicBrainzRecording(id: "2", title: "Song", length: nil, artistCredit: [ArtistCredit(name: "Artist")])
                ])
            })

        let result = await sut.resolve(track: Track(title: "Song", artist: "Artist"))

        #expect(result.first?.musicbrainzId == "2")
        #expect(await calls.count == 2)
    }

    @Test("resolve returns empty when API throws for every query")
    func resolveReturnsEmptyOnError() async {
        let sut = MusicBrainzMetadataDataSourceImpl(
            api: MusicBrainzStub { _, _, _ in
                throw StubError("network down")
            })

        let result = await sut.resolve(track: Track(title: "Missing", artist: "Missing"))

        #expect(result.isEmpty)
    }

    @Test("resolve passes fmt=json and limit=5")
    func resolvePassesParameters() async {
        let parameters = ParameterRecorder()
        let sut = MusicBrainzMetadataDataSourceImpl(
            api: MusicBrainzStub { _, fmt, limit in
                await parameters.set(fmt: fmt, limit: limit)
                return MusicBrainzResponse(recordings: [
                    MusicBrainzRecording(id: "x", title: "Song", length: nil, artistCredit: [ArtistCredit(name: "Artist")])
                ])
            })

        _ = await sut.resolve(track: Track(title: "Song", artist: "Artist"))
        let captured = await parameters.value

        #expect(captured?.fmt == "json")
        #expect(captured?.limit == 5)
    }
}

private actor QueryRecorder {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
    var count: Int { values.count }
}

private actor ParameterRecorder {
    private(set) var value: (fmt: String, limit: Int)?
    func set(fmt: String, limit: Int) { value = (fmt, limit) }
}
