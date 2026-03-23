import AppKit
import Testing

@testable import Views

@Suite("Hex color parsing")
struct HexColorTests {
    private func rgb(_ color: NSColor) -> (r: Double, g: Double, b: Double, a: Double) {
        guard let c = color.usingColorSpace(.sRGB) else { return (0, 0, 0, 0) }
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    private func parse(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double) {
        rgb(NSColor(parseHexColor(hex)))
    }

    @Test("6-digit hex parses correctly")
    func sixDigit() {
        let c = parse("#FF0000")
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 0.0) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
        #expect(abs(c.a - 1.0) < 0.01)
    }

    @Test("6-digit hex without hash")
    func sixDigitNoHash() {
        let c = parse("00FF00")
        #expect(abs(c.r - 0.0) < 0.01)
        #expect(abs(c.g - 1.0) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
    }

    @Test("8-digit hex with alpha")
    func eightDigit() {
        let c = parse("#FF000080")
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 0.0) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
        #expect(abs(c.a - 128.0 / 255.0) < 0.01)
    }

    @Test("3-digit shorthand hex")
    func threeDigit() {
        let c = parse("#F00")
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 0.0) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
    }

    @Test("white color")
    func white() {
        let c = parse("#FFFFFF")
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 1.0) < 0.01)
        #expect(abs(c.b - 1.0) < 0.01)
    }

    @Test("black color")
    func black() {
        let c = parse("#000000")
        #expect(abs(c.r - 0.0) < 0.01)
        #expect(abs(c.g - 0.0) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
    }

    @Test("typical config color with alpha")
    func configColor() {
        let c = parse("#FFFFFFD9")
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 1.0) < 0.01)
        #expect(abs(c.b - 1.0) < 0.01)
        #expect(abs(c.a - 217.0 / 255.0) < 0.01)
    }

    @Test("invalid hex returns white")
    func invalidHex() {
        let c = parse("not-a-color")
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 1.0) < 0.01)
        #expect(abs(c.b - 1.0) < 0.01)
    }

    @Test("mixed case hex")
    func mixedCase() {
        let c = parse("#aaBBcc")
        #expect(abs(c.r - 0xAA / 255.0) < 0.01)
        #expect(abs(c.g - 0xBB / 255.0) < 0.01)
        #expect(abs(c.b - 0xCC / 255.0) < 0.01)
    }
}
