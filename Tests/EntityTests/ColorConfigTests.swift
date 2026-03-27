import Foundation
import Testing

@testable import Entity

@Suite("ColorConfig")
struct ColorConfigTests {

    // MARK: - init(hex:)

    @Test("6-digit hex parses to correct RGBA")
    func sixDigitHex() {
        let c = ColorConfig(hex: "#FF0000")
        #expect(abs(c.red - 1.0) < 0.01)
        #expect(abs(c.green - 0.0) < 0.01)
        #expect(abs(c.blue - 0.0) < 0.01)
        #expect(abs(c.alpha - 1.0) < 0.01)
    }

    @Test("3-digit shorthand hex")
    func threeDigitHex() {
        let c = ColorConfig(hex: "#F00")
        #expect(abs(c.red - 1.0) < 0.01)
        #expect(abs(c.green - 0.0) < 0.01)
        #expect(abs(c.blue - 0.0) < 0.01)
    }

    @Test("8-digit hex with alpha")
    func eightDigitHex() {
        let c = ColorConfig(hex: "#FF000080")
        #expect(abs(c.red - 1.0) < 0.01)
        #expect(abs(c.alpha - 128.0 / 255.0) < 0.01)
    }

    @Test("hex without hash prefix")
    func noHashPrefix() {
        let c = ColorConfig(hex: "00FF00")
        #expect(abs(c.green - 1.0) < 0.01)
    }

    @Test("invalid hex returns white")
    func invalidHex() {
        let c = ColorConfig(hex: "not-a-color")
        #expect(c == .white)
    }

    @Test("empty string returns white")
    func emptyString() {
        let c = ColorConfig(hex: "")
        #expect(c == .white)
    }

    @Test("unsupported length (4 digits) returns white")
    func fourDigitHex() {
        let c = ColorConfig(hex: "#ABCD")
        #expect(c == .white)
    }

    // MARK: - hex computed property

    @Test("hex round-trip: 6-digit")
    func hexRoundTrip6() {
        let original = "#FF8000"
        let c = ColorConfig(hex: original)
        #expect(c.hex == original)
    }

    @Test("hex round-trip: 8-digit with alpha")
    func hexRoundTrip8() {
        let c = ColorConfig(hex: "#FF000080")
        #expect(c.hex.hasPrefix("#FF0000"))
        #expect(c.hex.count == 9)  // #RRGGBBAA
    }

    @Test("opaque color omits alpha in hex")
    func opaqueOmitsAlpha() {
        let c = ColorConfig(red: 1, green: 0, blue: 0)
        #expect(c.hex == "#FF0000")
    }

    // MARK: - HSB

    @Test("red HSB: hue near 0, saturation 1, brightness 1")
    func redHSB() {
        let hsb = ColorConfig(hex: "#FF0000").hsb
        #expect(abs(hsb.hue) < 0.02 || abs(hsb.hue - 1.0) < 0.02)
        #expect(abs(hsb.saturation - 1.0) < 0.01)
        #expect(abs(hsb.brightness - 1.0) < 0.01)
    }

    @Test("green HSB: hue near 0.33")
    func greenHSB() {
        let hsb = ColorConfig(hex: "#00FF00").hsb
        #expect(abs(hsb.hue - 0.333) < 0.02)
    }

    @Test("white HSB: saturation 0, brightness 1")
    func whiteHSB() {
        let hsb = ColorConfig.white.hsb
        #expect(abs(hsb.saturation) < 0.01)
        #expect(abs(hsb.brightness - 1.0) < 0.01)
    }

    @Test("black HSB: brightness 0")
    func blackHSB() {
        let hsb = ColorConfig.black.hsb
        #expect(abs(hsb.brightness) < 0.01)
    }

    // MARK: - init(hue:saturation:brightness:alpha:)

    @Test("red from HSB: hue 0, saturation 1, brightness 1")
    func redFromHSB() {
        let c = ColorConfig(hue: 0, saturation: 1, brightness: 1)
        #expect(abs(c.red - 1.0) < 0.01)
        #expect(abs(c.green) < 0.01)
        #expect(abs(c.blue) < 0.01)
    }

    @Test("green from HSB: hue ~0.333")
    func greenFromHSB() {
        let c = ColorConfig(hue: 1.0 / 3.0, saturation: 1, brightness: 1)
        #expect(abs(c.green - 1.0) < 0.01)
        #expect(abs(c.red) < 0.01)
    }

    @Test("blue from HSB: hue ~0.667")
    func blueFromHSB() {
        let c = ColorConfig(hue: 2.0 / 3.0, saturation: 1, brightness: 1)
        #expect(abs(c.blue - 1.0) < 0.01)
        #expect(abs(c.red) < 0.01)
    }

    @Test("white from HSB: saturation 0, brightness 1")
    func whiteFromHSB() {
        let c = ColorConfig(hue: 0, saturation: 0, brightness: 1)
        #expect(abs(c.red - 1.0) < 0.01)
        #expect(abs(c.green - 1.0) < 0.01)
        #expect(abs(c.blue - 1.0) < 0.01)
    }

    @Test("black from HSB: brightness 0")
    func blackFromHSB() {
        let c = ColorConfig(hue: 0, saturation: 0, brightness: 0)
        #expect(abs(c.red) < 0.01)
        #expect(abs(c.green) < 0.01)
        #expect(abs(c.blue) < 0.01)
    }

    @Test("HSB round-trip: hex → hsb → init(hue:) → hex")
    func hsbRoundTrip() {
        let original = ColorConfig(hex: "#FF8040")
        let hsb = original.hsb
        let reconstructed = ColorConfig(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)
        #expect(abs(original.red - reconstructed.red) < 0.02)
        #expect(abs(original.green - reconstructed.green) < 0.02)
        #expect(abs(original.blue - reconstructed.blue) < 0.02)
    }

    @Test("negative hue is normalized to valid RGB")
    func negativeHue() {
        let c = ColorConfig(hue: -0.15, saturation: 1, brightness: 1)
        #expect(c.red >= 0 && c.red <= 1)
        #expect(c.green >= 0 && c.green <= 1)
        #expect(c.blue >= 0 && c.blue <= 1)
    }

    @Test("hue >= 1 wraps around")
    func hueWraps() {
        let c1 = ColorConfig(hue: 0.0, saturation: 1, brightness: 1)
        let c2 = ColorConfig(hue: 1.0, saturation: 1, brightness: 1)
        #expect(abs(c1.red - c2.red) < 0.01)
        #expect(abs(c1.green - c2.green) < 0.01)
        #expect(abs(c1.blue - c2.blue) < 0.01)
    }

    @Test("hue = 1.5 wraps to 0.5")
    func hueOver1() {
        let c1 = ColorConfig(hue: 0.5, saturation: 1, brightness: 1)
        let c2 = ColorConfig(hue: 1.5, saturation: 1, brightness: 1)
        #expect(abs(c1.red - c2.red) < 0.01)
        #expect(abs(c1.green - c2.green) < 0.01)
        #expect(abs(c1.blue - c2.blue) < 0.01)
    }

    @Test("HSB alpha is preserved")
    func hsbAlpha() {
        let c = ColorConfig(hue: 0, saturation: 1, brightness: 1, alpha: 0.5)
        #expect(abs(c.alpha - 0.5) < 0.01)
    }

    // MARK: - hex byte clamping

    @Test("out-of-range values are clamped in hex output")
    func hexClamping() {
        let c = ColorConfig(red: 1.5, green: -0.1, blue: 0.5)
        let hex = c.hex
        #expect(hex.hasPrefix("#FF"))  // red clamped to 255
        #expect(hex.contains("00"))  // green clamped to 0
    }

    // MARK: - ExpressibleByStringLiteral

    @Test("string literal creates ColorConfig")
    func stringLiteral() {
        let c: ColorConfig = "#00FF00"
        #expect(abs(c.green - 1.0) < 0.01)
    }

    // MARK: - Codable

    @Test("encode then decode round-trip")
    func codableRoundTrip() throws {
        let original = ColorConfig(hex: "#AABBCC")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ColorConfig.self, from: data)
        #expect(abs(original.red - decoded.red) < 0.01)
        #expect(abs(original.green - decoded.green) < 0.01)
        #expect(abs(original.blue - decoded.blue) < 0.01)
    }

    @Test("decodes from JSON hex string")
    func decodesFromJSON() throws {
        let json = "\"#FF0000\""
        let data = json.data(using: .utf8)!
        let c = try JSONDecoder().decode(ColorConfig.self, from: data)
        #expect(abs(c.red - 1.0) < 0.01)
    }
}

@Suite("ColorStyle with ColorConfig")
struct ColorStyleColorConfigTests {

    @Test(".solid with string literal")
    func solidStringLiteral() {
        let style: ColorStyle = .solid("#FF0000")
        guard case .solid(let config) = style else {
            #expect(Bool(false), "Expected .solid")
            return
        }
        #expect(abs(config.red - 1.0) < 0.01)
    }

    @Test(".gradient with string literals")
    func gradientStringLiterals() {
        let style: ColorStyle = .gradient(["#FF0000", "#00FF00"])
        guard case .gradient(let configs) = style else {
            #expect(Bool(false), "Expected .gradient")
            return
        }
        #expect(configs.count == 2)
        #expect(abs(configs[0].red - 1.0) < 0.01)
        #expect(abs(configs[1].green - 1.0) < 0.01)
    }

    @Test("ColorStyle Codable round-trip for solid")
    func solidCodable() throws {
        let json = "\"#AABBCC\""
        let data = json.data(using: .utf8)!
        let style = try JSONDecoder().decode(ColorStyle.self, from: data)
        guard case .solid(let config) = style else {
            #expect(Bool(false), "Expected .solid")
            return
        }
        #expect(abs(config.red - 0xAA / 255.0) < 0.01)
    }

    @Test("ColorStyle Codable round-trip for gradient")
    func gradientCodable() throws {
        let json = "[\"#FF0000\", \"#00FF00\"]"
        let data = json.data(using: .utf8)!
        let style = try JSONDecoder().decode(ColorStyle.self, from: data)
        guard case .gradient(let configs) = style else {
            #expect(Bool(false), "Expected .gradient")
            return
        }
        #expect(configs.count == 2)
    }
}
