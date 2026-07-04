import AppKit
import Domain
import Testing

@testable import Views

@Suite("SwiftUIResolver")
struct SwiftUIResolverTests {
    private let resolver = SwiftUIResolverImpl()

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

    // MARK: - color(from:at:)

    @MainActor
    @Test("sampling a two-color gradient at the ends returns the endpoints")
    func sampledColorEndpoints() {
        let style = ColorStyle.gradient(["#FF0000", "#0000FF"])
        let low = rgb(NSColor(resolver.color(from: style, at: 0)))
        let high = rgb(NSColor(resolver.color(from: style, at: 1)))
        #expect(abs(low.r - 1.0) < 0.01)
        #expect(abs(low.b - 0.0) < 0.01)
        #expect(abs(high.b - 1.0) < 0.01)
        #expect(abs(high.r - 0.0) < 0.01)
    }

    @MainActor
    @Test("sampling the midpoint blends the two colors")
    func sampledColorMidpoint() {
        let c = rgb(NSColor(resolver.color(from: .gradient(["#000000", "#FFFFFF"]), at: 0.5)))
        #expect(abs(c.r - 0.5) < 0.02)
        #expect(abs(c.g - 0.5) < 0.02)
        #expect(abs(c.b - 0.5) < 0.02)
    }

    @MainActor
    @Test("sampling a solid style ignores the fraction")
    func sampledColorSolid() {
        let c = rgb(NSColor(resolver.color(from: .solid("#00FF00"), at: 0.3)))
        #expect(abs(c.g - 1.0) < 0.01)
    }

    @MainActor
    @Test("sampling clamps out-of-range fractions")
    func sampledColorClamps() {
        let style = ColorStyle.gradient(["#FF0000", "#0000FF"])
        let below = rgb(NSColor(resolver.color(from: style, at: -1)))
        let above = rgb(NSColor(resolver.color(from: style, at: 2)))
        #expect(abs(below.r - 1.0) < 0.01)
        #expect(abs(above.b - 1.0) < 0.01)
    }

    // MARK: - gradient(from:)

    @MainActor
    @Test("gradient(from:) does not crash for solid, single, and multi-color styles")
    func gradientBuilds() {
        _ = resolver.gradient(from: .solid("#FF0000"))
        _ = resolver.gradient(from: .gradient(["#FF0000"]))
        _ = resolver.gradient(from: .gradient(["#FF0000", "#00FF00", "#0000FF"]))
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

    // MARK: - hueShifted color

    @MainActor
    @Test("hue shifted color from solid style does not crash")
    func hueShiftedSolid() {
        _ = resolver.color(.solid("#AAAAFF"), hueShiftedBy: 0.1, opacity: 0.8)
    }

    @MainActor
    @Test("hue shifted color with zero shift returns similar color")
    func hueShiftedZero() {
        let original = resolver.color(.solid("#FF0000"), hueShiftedBy: 0, opacity: 1.0)
        let c = rgb(NSColor(original))
        #expect(abs(c.r - 1.0) < 0.05)
    }

    @MainActor
    @Test("hue shifted color from gradient uses first color")
    func hueShiftedGradient() {
        _ = resolver.color(.gradient(["#FF0000", "#00FF00"]), hueShiftedBy: 0.5, opacity: 0.5)
    }

    // MARK: - hsbComponents(from:)

    @MainActor
    @Test("hsbComponents of red returns hue near 0")
    func hsbRed() {
        let hsb = resolver.hsbComponents(from: .solid("#FF0000"))
        #expect(abs(hsb.hue) < 0.02 || abs(hsb.hue - 1.0) < 0.02)
        #expect(abs(hsb.saturation - 1.0) < 0.01)
        #expect(abs(hsb.brightness - 1.0) < 0.01)
    }

    @MainActor
    @Test("hsbComponents of white returns zero saturation")
    func hsbWhite() {
        let hsb = resolver.hsbComponents(from: .solid("#FFFFFF"))
        #expect(abs(hsb.saturation) < 0.01)
        #expect(abs(hsb.brightness - 1.0) < 0.01)
    }

    @MainActor
    @Test("hsbComponents of gradient uses first color")
    func hsbGradient() {
        let hsb = resolver.hsbComponents(from: .gradient(["#00FF00", "#FF0000"]))
        // Green: hue ~0.33
        #expect(abs(hsb.hue - 0.333) < 0.02)
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

    @MainActor
    @Test("lineHeight with zero spacing equals font ascent+descent+leading")
    func lineHeightZeroSpacing() {
        let height = resolver.lineHeight(from: TextAppearance(spacing: 0, fontName: "Helvetica", fontSize: 14))
        #expect(height > 0)
        let withSpacing = resolver.lineHeight(from: TextAppearance(spacing: 6, fontName: "Helvetica", fontSize: 14))
        #expect(withSpacing > height)
    }

    @MainActor
    @Test("lineHeight with unknown font falls back to system font")
    func lineHeightUnknownFont() {
        let height = resolver.lineHeight(from: TextAppearance(fontName: "NonExistentFont999", fontSize: 16))
        #expect(height > 0)
    }

    @MainActor
    @Test("lineHeight increases with spacing")
    func lineHeightScalesWithSpacing() {
        let noSpacing = resolver.lineHeight(from: TextAppearance(spacing: 0, fontSize: 14))
        let largeSpacing = resolver.lineHeight(from: TextAppearance(spacing: 20, fontSize: 14))
        #expect(largeSpacing > noSpacing)
    }
}
