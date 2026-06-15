import Foundation
import Testing

@testable import Entity

@Suite("DecodeEffectConfig")
struct DecodeEffectConfigTests {

    private func decode(_ json: String) throws -> DecodeEffectConfig {
        try JSONDecoder().decode(DecodeEffectConfig.self, from: Data(json.utf8))
    }

    // MARK: - processing_color

    @Test("decodes processing_color as a solid color")
    func decodesProcessingColor() throws {
        let config = try decode(##"{"processing_color": "#FF00FF"}"##)
        #expect(config.processingColor == .solid("#FF00FFFF"))
    }

    @Test("decodes processing_color as a gradient")
    func decodesProcessingColorGradient() throws {
        let config = try decode(##"{"processing_color": ["#FF0000", "#00FF00"]}"##)
        #expect(config.processingColor == .gradient(["#FF0000FF", "#00FF00FF"]))
    }

    @Test("falls back to the green default when processing_color is absent")
    func defaultsProcessingColor() throws {
        let config = try decode(#"{"duration": 1.0}"#)
        #expect(config.processingColor == DecodeEffectConfig.defaults.processingColor)
        #expect(config.processingColor == .solid("#4ADE80FF"))
    }

    @Test("default processing_color survives a full empty object decode")
    func defaultsOnEmptyObject() throws {
        let config = try decode("{}")
        #expect(config.processingColor == .solid("#4ADE80FF"))
        #expect(config.duration.value == 0.8)
    }

    // MARK: - encode round-trip

    @Test("encodes processing_color under the snake_case key")
    func encodesProcessingColorKey() throws {
        let data = try JSONEncoder().encode(DecodeEffectConfig.defaults)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("processing_color"))
    }

    @Test("encode then decode preserves a custom processing_color")
    func roundTripProcessingColor() throws {
        let original = try decode(##"{"processing_color": "#123456"}"##)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(DecodeEffectConfig.self, from: data)
        #expect(restored.processingColor == original.processingColor)
        #expect(restored.processingColor == .solid("#123456FF"))
    }
}
