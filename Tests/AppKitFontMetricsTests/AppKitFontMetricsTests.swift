import AppKit
import Domain
import Testing

@testable import AppKitFontMetrics

@Suite("AppKitFontMetrics")
struct AppKitFontMetricsTests {
    @MainActor
    @Test("lineHeight uses the named font's metrics plus spacing on both sides")
    func namedFont() throws {
        let font = try #require(NSFont(name: "Helvetica", size: 24))
        let expected = ceil(font.ascender - font.descender + font.leading) + 3 * 2

        #expect(AppKitFontMetrics().lineHeight(fontName: "Helvetica", fontSize: 24, spacing: 3) == expected)
    }

    @MainActor
    @Test("lineHeight falls back to the system font when no font or family has the name")
    func unknownFontFallsBackToSystemFont() {
        let font = NSFont.systemFont(ofSize: 18)
        let expected = ceil(font.ascender - font.descender + font.leading)

        #expect(AppKitFontMetrics().lineHeight(fontName: "no-such-font-372", fontSize: 18, spacing: 0) == expected)
    }

    @MainActor
    @Test("lineHeight grows with the font size")
    func largerFontIsTaller() {
        let metrics = AppKitFontMetrics()

        #expect(
            metrics.lineHeight(fontName: "Helvetica", fontSize: 48, spacing: 0)
                > metrics.lineHeight(fontName: "Helvetica", fontSize: 12, spacing: 0))
    }
}
