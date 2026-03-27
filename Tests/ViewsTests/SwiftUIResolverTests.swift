import AppKit
import Domain
import Testing

@testable import Views

@Suite("SwiftUIResolver")
struct SwiftUIResolverTests {
    private let resolver = LiveSwiftUIResolver()

    private func rgb(_ color: NSColor) -> (r: Double, g: Double, b: Double, a: Double) {
        guard let c = color.usingColorSpace(.sRGB) else { return (0, 0, 0, 0) }
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    // MARK: - color(from:)

    @MainActor
    @Test("6-digit hex parses correctly")
    func colorSixDigit() {
        let c = rgb(NSColor(resolver.color(from: "#FF0000")))
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 0.0) < 0.01)
    }

    @MainActor
    @Test("3-digit shorthand hex")
    func colorThreeDigit() {
        let c = rgb(NSColor(resolver.color(from: "#F00")))
        #expect(abs(c.r - 1.0) < 0.01)
    }

    @MainActor
    @Test("8-digit hex with alpha")
    func colorEightDigit() {
        let c = rgb(NSColor(resolver.color(from: "#FF000080")))
        #expect(abs(c.a - 128.0 / 255.0) < 0.01)
    }

    @MainActor
    @Test("invalid hex returns white")
    func colorInvalid() {
        let c = rgb(NSColor(resolver.color(from: "not-a-color")))
        #expect(abs(c.r - 1.0) < 0.01)
    }

    @MainActor
    @Test("4-digit hex (unsupported length) returns white")
    func colorFourDigit() {
        let c = rgb(NSColor(resolver.color(from: "#ABCD")))
        #expect(abs(c.r - 1.0) < 0.01)
    }

    @MainActor
    @Test("5-digit hex (unsupported length) returns white")
    func colorFiveDigit() {
        let c = rgb(NSColor(resolver.color(from: "#ABCDE")))
        #expect(abs(c.r - 1.0) < 0.01)
    }

    // MARK: - solidColor(from:)

    @MainActor
    @Test("solid style returns parsed color")
    func solidColor() {
        let c = rgb(NSColor(resolver.solidColor(from: .solid("#00FF00"))))
        #expect(abs(c.g - 1.0) < 0.01)
    }

    @MainActor
    @Test("gradient style returns first color")
    func gradientSolidColor() {
        let c = rgb(NSColor(resolver.solidColor(from: .gradient(["#FF0000", "#00FF00"]))))
        #expect(abs(c.r - 1.0) < 0.01)
    }

    @MainActor
    @Test("empty gradient returns white")
    func emptyGradientSolidColor() {
        let c = rgb(NSColor(resolver.solidColor(from: .gradient([]))))
        #expect(abs(c.r - 1.0) < 0.01)
    }

    // MARK: - shapeStyle(from:)

    @MainActor
    @Test("solid shapeStyle does not crash")
    func solidShapeStyle() {
        _ = resolver.shapeStyle(from: .solid("#FF0000"))
    }

    @MainActor
    @Test("gradient shapeStyle with multiple colors does not crash")
    func gradientShapeStyle() {
        _ = resolver.shapeStyle(from: .gradient(["#FF0000", "#00FF00", "#0000FF"]))
    }

    @MainActor
    @Test("gradient shapeStyle with single color does not crash")
    func singleGradientShapeStyle() {
        _ = resolver.shapeStyle(from: .gradient(["#FF0000"]))
    }

    // MARK: - font(from:)

    @MainActor
    @Test("font with default weight")
    func fontDefault() {
        let style = TextAppearance(fontName: "Helvetica", fontSize: 16, fontWeight: "regular", color: .solid("#FFFFFF"), shadow: .solid("#000000"))
        _ = resolver.font(from: style)
    }

    @MainActor
    @Test("font with bold weight")
    func fontBold() {
        let style = TextAppearance(fontName: "Helvetica", fontSize: 16, fontWeight: "bold", color: .solid("#FFFFFF"), shadow: .solid("#000000"))
        _ = resolver.font(from: style)
    }

    @MainActor
    @Test("font with all weight variants")
    func fontAllWeights() {
        for weight in ["ultralight", "thin", "light", "medium", "semibold", "bold", "heavy", "black", "regular", "unknown"] {
            let style = TextAppearance(fontName: "Helvetica", fontSize: 14, fontWeight: weight, color: .solid("#FFF"), shadow: .solid("#000"))
            _ = resolver.font(from: style)
        }
    }

    // MARK: - lineHeight(from:)

    @MainActor
    @Test("lineHeight returns positive value")
    func lineHeightPositive() {
        let style = TextAppearance(spacing: 4, fontName: "Helvetica", fontSize: 16)
        let height = resolver.lineHeight(from: style)
        #expect(height > 0)
    }

    @MainActor
    @Test("lineHeight increases with font size")
    func lineHeightScalesWithSize() {
        let small = resolver.lineHeight(from: TextAppearance(fontSize: 12))
        let large = resolver.lineHeight(from: TextAppearance(fontSize: 24))
        #expect(large > small)
    }
}
