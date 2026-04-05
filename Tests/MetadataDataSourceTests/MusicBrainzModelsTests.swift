import Foundation
import Testing

@testable import MetadataDataSource

@Suite("MusicBrainz Models")
struct MusicBrainzModelsTests {
    // MARK: - MusicBrainzRecording

    @Suite("MusicBrainzRecording")
    struct Recording {
        @Test("artistName returns first artist credit name")
        func artistName() {
            let recording = MusicBrainzRecording(
                id: "1", title: "Song",
                length: nil, artistCredit: [ArtistCredit(name: "Artist")]
            )
            #expect(recording.artistName == "Artist")
        }

        @Test("artistName returns nil when no credits")
        func artistNameNil() {
            let recording = MusicBrainzRecording(
                id: "1", title: "Song",
                length: nil, artistCredit: nil
            )
            #expect(recording.artistName == nil)
        }

        @Test("artistName returns nil when credits empty")
        func artistNameEmpty() {
            let recording = MusicBrainzRecording(
                id: "1", title: "Song",
                length: nil, artistCredit: []
            )
            #expect(recording.artistName == nil)
        }

        @Test("duration converts milliseconds to seconds")
        func duration() {
            let recording = MusicBrainzRecording(
                id: "1", title: "Song",
                length: 240000, artistCredit: nil
            )
            #expect(recording.duration == 240.0)
        }

        @Test("duration returns nil when length is nil")
        func durationNil() {
            let recording = MusicBrainzRecording(
                id: "1", title: "Song",
                length: nil, artistCredit: nil
            )
            #expect(recording.duration == nil)
        }
    }

    // MARK: - JSON Decoding

    @Suite("JSON decoding")
    struct Decoding {
        @Test("decodes MusicBrainz API response")
        func decodeResponse() throws {
            let json = """
                {
                    "recordings": [
                        {
                            "id": "abc-123",
                            "title": "Numb",
                            "length": 187000,
                            "artist-credit": [{"name": "Linkin Park"}]
                        }
                    ]
                }
                """.data(using: .utf8)!

            let response = try JSONDecoder().decode(MusicBrainzResponse.self, from: json)
            #expect(response.recordings.count == 1)
            #expect(response.recordings[0].id == "abc-123")
            #expect(response.recordings[0].title == "Numb")
            #expect(response.recordings[0].artistName == "Linkin Park")
            #expect(response.recordings[0].duration == 187.0)
        }

        @Test("decodes response with missing optional fields")
        func decodeMissingOptionals() throws {
            let json = """
                {
                    "recordings": [
                        {
                            "id": "xyz-789",
                            "title": "Unknown"
                        }
                    ]
                }
                """.data(using: .utf8)!

            let response = try JSONDecoder().decode(MusicBrainzResponse.self, from: json)
            #expect(response.recordings[0].length == nil)
            #expect(response.recordings[0].artistCredit == nil)
            #expect(response.recordings[0].artistName == nil)
            #expect(response.recordings[0].duration == nil)
        }

        @Test("decodes empty recordings array")
        func decodeEmpty() throws {
            let json = """
                {"recordings": []}
                """.data(using: .utf8)!

            let response = try JSONDecoder().decode(MusicBrainzResponse.self, from: json)
            #expect(response.recordings.isEmpty)
        }
    }
}
