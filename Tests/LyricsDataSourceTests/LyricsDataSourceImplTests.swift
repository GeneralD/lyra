import Domain
import Foundation
import Testing

@testable import LyricsDataSource

@Suite("LyricsDataSourceImpl")
struct LyricsDataSourceImplTests {
    @Test("get returns decoded result when plain lyrics exist")
    func getReturnsDecodedResult() async {
        let dataSource = LyricsDataSourceImpl { request in
            #expect(request.url?.absoluteString.contains("/get?") == true)
            return try JSONEncoder().encode(
                LyricsResult(trackName: "Numb", artistName: "Linkin Park", plainLyrics: "I've become so numb")
            )
        }

        let result = await dataSource.get(title: "Numb", artist: "Linkin Park", duration: 187)

        #expect(result?.trackName == "Numb")
        #expect(result?.artistName == "Linkin Park")
        #expect(result?.plainLyrics == "I've become so numb")
    }

    @Test("get returns nil when decoded result has no lyrics")
    func getReturnsNilWithoutLyrics() async {
        let dataSource = LyricsDataSourceImpl { _ in
            try JSONEncoder().encode(
                LyricsResult(trackName: "Song", artistName: "Artist", plainLyrics: nil, syncedLyrics: nil)
            )
        }

        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)

        #expect(result == nil)
    }

    @Test("search returns decoded results")
    func searchReturnsDecodedResults() async {
        let dataSource = LyricsDataSourceImpl { request in
            #expect(request.url?.absoluteString.contains("/search?") == true)
            return try JSONEncoder().encode([
                LyricsResult(trackName: "Song A", artistName: "Artist A", syncedLyrics: "[00:00.00]Line"),
                LyricsResult(trackName: "Song B", artistName: "Artist B", plainLyrics: "Plain line"),
            ])
        }

        let result = await dataSource.search(query: "song")

        #expect(result?.count == 2)
        #expect(result?.first?.trackName == "Song A")
        #expect(result?.last?.trackName == "Song B")
    }

    @Test("search returns nil when request performer throws")
    func searchReturnsNilOnRequestError() async {
        let dataSource = LyricsDataSourceImpl { _ in
            throw LyricsDataSourceStubError()
        }

        let result = await dataSource.search(query: "song")

        #expect(result == nil)
    }

    @Test("get returns result when only synced lyrics exist")
    func getReturnsSyncedOnly() async {
        let dataSource = LyricsDataSourceImpl { _ in
            try JSONEncoder().encode(
                LyricsResult(trackName: "Song", artistName: "Artist", plainLyrics: nil, syncedLyrics: "[00:00.00]Line")
            )
        }

        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)

        #expect(result?.syncedLyrics == "[00:00.00]Line")
        #expect(result?.plainLyrics == nil)
    }

    @Test("get returns nil when request performer throws")
    func getReturnsNilOnRequestError() async {
        let dataSource = LyricsDataSourceImpl { _ in
            throw LyricsDataSourceStubError()
        }

        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)

        #expect(result == nil)
    }

    @Test("get returns nil when response is not decodable")
    func getReturnsNilOnInvalidJSON() async {
        let dataSource = LyricsDataSourceImpl { _ in
            Data("not json".utf8)
        }

        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)

        #expect(result == nil)
    }
}

private struct LyricsDataSourceStubError: Error, Sendable {}
