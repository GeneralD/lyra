import Foundation
import Testing

@testable import Entity

@Suite("NowPlayingInfo")
struct NowPlayingInfoSpec {
    @Test("encodes and decodes round-trip")
    func roundTrip() throws {
        let info = NowPlayingInfo(
            title: "Brave Shine",
            artist: "Aimer",
            album: "DAWN",
            duration: 233.5,
            elapsedTime: 90.0,
            lyrics: "La la la",
            syncedLyrics: [LyricLine(time: 0, text: "Start")],
            currentLyric: "Start"
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(NowPlayingInfo.self, from: data)
        #expect(decoded.title == "Brave Shine")
        #expect(decoded.artist == "Aimer")
        #expect(decoded.album == "DAWN")
        #expect(decoded.duration == 233.5)
        #expect(decoded.syncedLyrics?.count == 1)
        #expect(decoded.currentLyric == "Start")
    }

    @Test("default init has all nil")
    func defaultInit() {
        let info = NowPlayingInfo()
        #expect(info.title == nil)
        #expect(info.artist == nil)
        #expect(info.duration == nil)
        #expect(info.lyrics == nil)
        #expect(info.syncedLyrics == nil)
    }

    @Test("decodes from JSON with missing optional fields")
    func decodeMissing() throws {
        let json = "{}".data(using: .utf8)!
        let info = try JSONDecoder().decode(NowPlayingInfo.self, from: json)
        #expect(info.title == nil)
        #expect(info.artist == nil)
    }
}
