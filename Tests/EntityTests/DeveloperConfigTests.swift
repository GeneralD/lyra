import Foundation
import Testing

@testable import Entity

@Suite("DeveloperConfig")
struct DeveloperConfigTests {

    private func decode(_ json: String) throws -> DeveloperConfig {
        try JSONDecoder().decode(DeveloperConfig.self, from: Data(json.utf8))
    }

    // MARK: - memberwise init

    @Test("the memberwise init defaults to a disabled trace with no file")
    func memberwiseDefaults() {
        let config = DeveloperConfig()
        #expect(config.lyricsResolution == false)
        #expect(config.lyricsResolutionFile == nil)
    }

    @Test("the memberwise init stores the given values")
    func memberwiseValues() {
        let config = DeveloperConfig(lyricsResolution: true, lyricsResolutionFile: "/tmp/x.log")
        #expect(config.lyricsResolution)
        #expect(config.lyricsResolutionFile == "/tmp/x.log")
    }

    // MARK: - decode

    @Test("decodes an enabled trace with an explicit file")
    func decodesValues() throws {
        let config = try decode(##"{"lyrics_resolution": true, "lyrics_resolution_file": "~/trace.log"}"##)
        #expect(config.lyricsResolution)
        #expect(config.lyricsResolutionFile == "~/trace.log")
    }

    @Test("absent keys decode to the disabled defaults")
    func defaultsWhenAbsent() throws {
        let config = try decode("{}")
        #expect(config.lyricsResolution == false)
        #expect(config.lyricsResolutionFile == nil)
    }

    @Test("a blank file is normalized to nil at the decode boundary")
    func blankFileNormalizedToNil() throws {
        let config = try decode(##"{"lyrics_resolution": true, "lyrics_resolution_file": "   "}"##)
        #expect(config.lyricsResolution)
        #expect(config.lyricsResolutionFile == nil)
    }

    // MARK: - encode round-trip

    @Test("encodes under the snake_case keys")
    func encodesKeys() throws {
        let data = try JSONEncoder().encode(DeveloperConfig(lyricsResolution: true, lyricsResolutionFile: "/tmp/x.log"))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("lyrics_resolution"))
        #expect(json.contains("lyrics_resolution_file"))
    }

    @Test("a nil file is omitted from the encoded output")
    func encodeOmitsNilFile() throws {
        let data = try JSONEncoder().encode(DeveloperConfig(lyricsResolution: true))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("lyrics_resolution"))
        #expect(!json.contains("lyrics_resolution_file"))
    }

    @Test("encode then decode preserves the values")
    func roundTrip() throws {
        let original = DeveloperConfig(lyricsResolution: true, lyricsResolutionFile: "/var/log/lyra.log")
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(DeveloperConfig.self, from: data)
        #expect(restored == original)
    }
}
