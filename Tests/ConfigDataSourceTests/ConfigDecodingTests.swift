import Domain
import Foundation
import TOMLKit
import Testing

@testable import ConfigDataSource

// MARK: - Helper

private func decode(_ toml: String) throws -> AppConfig {
    let table = try TOMLTable(string: toml)
    return try TOMLDecoder().decode(AppConfig.self, from: table)
}

// MARK: - Default values

@Suite("Default value resolution")
struct DefaultValueTests {
    @Test("empty TOML produces all defaults")
    func emptyToml() throws {
        let config = try decode("")
        #expect(config.text.default.fontName == "Helvetica Neue")
        #expect(config.text.default.fontSize == 12)
        #expect(config.text.default.fontWeight == "regular")
        #expect(config.text.default.spacing == 6)
        #expect(config.artwork.size.value == 96)
        #expect(config.artwork.opacity.value == 1.0)
        #expect(config.ripple.enabled == true)
        #expect(config.ripple.color == "#AAAAFFFF")
        #expect(config.ripple.radius.value == 60)
        #expect(config.ai == nil)
    }

    @Test("missing [text] section uses TextConfig.defaults")
    func noTextSection() throws {
        let config = try decode(
            """
            screen = "main"
            """)
        #expect(config.text.default.fontName == "Helvetica Neue")
    }

    @Test("missing [artwork] section uses ArtworkConfig.defaults")
    func noArtworkSection() throws {
        let config = try decode("")
        #expect(config.artwork.size.value == 96)
        #expect(config.artwork.opacity.value == 1.0)
    }

    @Test("missing [ripple] section uses RippleConfig.defaults")
    func noRippleSection() throws {
        let config = try decode("")
        #expect(config.ripple.enabled == true)
        #expect(config.ripple.radius.value == 60)
        #expect(config.ripple.duration.value == 0.6)
        #expect(config.ripple.idle.value == 1)
    }

    @Test("missing [ai] section produces nil")
    func noAiSection() throws {
        let config = try decode("")
        #expect(config.ai == nil)
    }

    @Test("missing [lyrics] section produces nil")
    func noLyricsSection() throws {
        let config = try decode("")
        #expect(config.lyrics == nil)
    }
}

// MARK: - Wallpaper config (TOML)

@Suite("Wallpaper TOML decoding")
struct WallpaperTomlDecodingTests {
    @Test("bare string wallpaper decodes location only")
    func bareString() throws {
        let config = try decode(
            """
            wallpaper = "loop.mp4"
            """)
        #expect(config.wallpaper?.items.first?.location == "loop.mp4")
        #expect(config.wallpaper?.items.first?.start == nil)
        #expect(config.wallpaper?.items.first?.end == nil)
        #expect(config.wallpaper?.items.first?.scale == 1.0)
    }

    @Test("[wallpaper] table with location only")
    func tableLocationOnly() throws {
        let config = try decode(
            """
            [wallpaper]
            location = "bg.mp4"
            """)
        #expect(config.wallpaper?.items.first?.location == "bg.mp4")
        #expect(config.wallpaper?.items.first?.start == nil)
        #expect(config.wallpaper?.items.first?.end == nil)
        #expect(config.wallpaper?.items.first?.scale == 1.0)
    }

    @Test("[wallpaper] table with start and end")
    func tableWithTrim() throws {
        let config = try decode(
            """
            [wallpaper]
            location = "https://www.youtube.com/watch?v=XXXXX"
            start = "0:30"
            end = "3:45"
            """)
        #expect(config.wallpaper?.items.first?.location == "https://www.youtube.com/watch?v=XXXXX")
        #expect(config.wallpaper?.items.first?.start == 30.0)
        #expect(config.wallpaper?.items.first?.end == 225.0)
    }

    @Test("[wallpaper] table with scale")
    func tableWithScale() throws {
        let config = try decode(
            """
            [wallpaper]
            location = "https://www.youtube.com/watch?v=XXXXX"
            scale = 1.25
            """)
        #expect(config.wallpaper?.items.first?.location == "https://www.youtube.com/watch?v=XXXXX")
        #expect(config.wallpaper?.items.first?.scale == 1.25)
    }

    @Test("[[wallpaper.items]] table with per-item scale")
    func itemsWithScale() throws {
        let config = try decode(
            """
            [wallpaper]
            mode = "cycle"

            [[wallpaper.items]]
            location = "a.mp4"
            scale = 1.1

            [[wallpaper.items]]
            location = "b.mp4"
            scale = 1.35
            """)
        #expect(config.wallpaper?.items.map(\.scale) == [1.1, 1.35])
    }

    @Test("[wallpaper] table with start only")
    func tableStartOnly() throws {
        let config = try decode(
            """
            [wallpaper]
            location = "video.mp4"
            start = "1:00"
            """)
        #expect(config.wallpaper?.items.first?.start == 60.0)
        #expect(config.wallpaper?.items.first?.end == nil)
    }

    @Test("missing wallpaper produces nil")
    func missingWallpaper() throws {
        let config = try decode("")
        #expect(config.wallpaper == nil)
    }

    @Test("[wallpaper] start >= end discards end")
    func startGteEnd() throws {
        let config = try decode(
            """
            [wallpaper]
            location = "v.mp4"
            start = "2:00"
            end = "1:00"
            """)
        #expect(config.wallpaper?.items.first?.start == 120.0)
        #expect(config.wallpaper?.items.first?.end == nil)
    }
}

// MARK: - Text style inheritance chain

@Suite("Text style inheritance")
struct TextStyleInheritanceTests {
    @Test("title/artist/lyric/highlight inherit from default when not specified")
    func inheritFromDefault() throws {
        let config = try decode(
            """
            [text.default]
            font = "Custom Font"
            size = 20
            """)
        #expect(config.text.title.fontName == "Custom Font")
        #expect(config.text.artist.fontName == "Custom Font")
        #expect(config.text.lyric.fontName == "Custom Font")
        #expect(config.text.highlight.fontName == "Custom Font")
    }

    @Test("title overrides size, titleDefaults override weight, rest from default")
    func titleOverridesSize() throws {
        let config = try decode(
            """
            [text.default]
            font = "Custom Font"
            size = 14
            weight = "light"

            [text.title]
            size = 24
            """)
        #expect(config.text.title.fontSize == 24)
        #expect(config.text.title.fontName == "Custom Font")
        // titleDefaults provides weight="bold", which takes priority over default's "light"
        #expect(config.text.title.fontWeight == "bold")
    }

    @Test("artist overrides weight but inherits other fields from default")
    func artistOverridesWeight() throws {
        let config = try decode(
            """
            [text.default]
            font = "Custom Font"
            size = 14

            [text.artist]
            weight = "bold"
            """)
        #expect(config.text.artist.fontWeight == "bold")
        #expect(config.text.artist.fontName == "Custom Font")
        #expect(config.text.artist.fontSize == 14)
    }

    @Test("highlight inherits from lyric, not directly from default")
    func highlightInheritsFromLyric() throws {
        let config = try decode(
            """
            [text.default]
            font = "Default Font"

            [text.lyric]
            font = "Lyric Font"
            """)
        #expect(config.text.highlight.fontName == "Lyric Font")
    }

    @Test("lyric color change propagates to unspecified highlight")
    func lyricColorPropagesToHighlight() throws {
        let config = try decode(
            """
            [text.lyric]
            spacing = 10
            """)
        #expect(config.text.highlight.spacing == 10)
    }

    @Test("unspecified title section still applies titleDefaults: size=18, weight=bold")
    func titleUnspecifiedAppliesLayerDefaults() throws {
        let config = try decode("")
        #expect(config.text.title.fontSize == 18)
        #expect(config.text.title.fontWeight == "bold")
    }

    @Test("empty title section also applies titleDefaults")
    func emptyTitleSectionAppliesLayerDefaults() throws {
        let config = try decode(
            """
            [text.title]
            """)
        #expect(config.text.title.fontSize == 18)
        #expect(config.text.title.fontWeight == "bold")
    }

    @Test("unspecified artist section still applies artistDefaults: weight=medium")
    func artistUnspecifiedAppliesLayerDefaults() throws {
        let config = try decode("")
        #expect(config.text.artist.fontWeight == "medium")
    }

    @Test("empty artist section also applies artistDefaults")
    func emptyArtistSectionAppliesLayerDefaults() throws {
        let config = try decode(
            """
            [text.artist]
            """)
        #expect(config.text.artist.fontWeight == "medium")
    }

    @Test("unspecified highlight applies highlightDefaults: gold gradient")
    func highlightUnspecifiedAppliesLayerDefaults() throws {
        let config = try decode("")
        #expect(config.text.highlight.color == .gradient(["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"]))
    }

    @Test("empty highlight section also applies highlightDefaults")
    func emptyHighlightSectionAppliesLayerDefaults() throws {
        let config = try decode(
            """
            [text.highlight]
            """)
        #expect(config.text.highlight.color == .gradient(["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"]))
    }
}

// MARK: - FlexibleDouble

@Suite("FlexibleDouble decoding")
struct FlexibleDoubleTests {
    @Test("TOML integer decodes as FlexibleDouble")
    func integerValue() throws {
        let config = try decode(
            """
            [text.default]
            size = 12
            """)
        #expect(config.text.default.fontSize == 12.0)
    }

    @Test("TOML float decodes as FlexibleDouble")
    func floatValue() throws {
        let config = try decode(
            """
            [text.decode_effect]
            duration = 0.8
            """)
        #expect(config.text.decodeEffect.duration.value == 0.8)
    }

    @Test("TOML integer spacing decodes correctly")
    func integerSpacing() throws {
        let config = try decode(
            """
            [text.default]
            spacing = 6
            """)
        #expect(config.text.default.spacing == 6.0)
    }
}

// MARK: - Partial specification

@Suite("Partial field specification")
struct PartialSpecificationTests {
    @Test("ripple with only color specified fills remaining with defaults")
    func ripplePartial() throws {
        let config = try decode(
            """
            [ripple]
            color = "#FF0000FF"
            """)
        #expect(config.ripple.color == "#FF0000FF")
        #expect(config.ripple.enabled == true)
        #expect(config.ripple.radius.value == 60)
        #expect(config.ripple.duration.value == 0.6)
        #expect(config.ripple.idle.value == 1)
    }

    @Test("artwork with only opacity specified fills size with default")
    func artworkPartial() throws {
        let config = try decode(
            """
            [artwork]
            opacity = 0.5
            """)
        #expect(config.artwork.opacity.value == 0.5)
        #expect(config.artwork.size.value == 96)
    }

    @Test("decode_effect with only duration specified fills charset with all")
    func decodeEffectPartial() throws {
        let config = try decode(
            """
            [text.decode_effect]
            duration = 1.5
            """)
        #expect(config.text.decodeEffect.duration.value == 1.5)
        #expect(config.text.decodeEffect.charset == Set(CharsetName.allCases))
    }
}

// MARK: - ColorStyle polymorphic decoding

@Suite("ColorStyle polymorphic decoding")
struct ColorStyleTests {
    @Test("string color decodes as solid")
    func solidColor() throws {
        let config = try decode(
            """
            [text.default]
            color = "#FFF"
            """)
        #expect(config.text.default.color == .solid("#FFF"))
    }

    @Test("array color decodes as gradient")
    func gradientColor() throws {
        let config = try decode(
            """
            [text.default]
            color = ["#AAA", "#BBB"]
            """)
        #expect(config.text.default.color == .gradient(["#AAA", "#BBB"]))
    }

    @Test("shadow string decodes as solid ColorStyle")
    func shadowColor() throws {
        let config = try decode(
            """
            [text.default]
            shadow = "#000"
            """)
        #expect(config.text.default.shadow == .solid("#000"))
    }
}

// MARK: - Charset polymorphic decoding

@Suite("Charset polymorphic decoding")
struct CharsetTests {
    @Test("single string charset decodes as single-element set")
    func singleCharset() throws {
        let config = try decode(
            """
            [text.decode_effect]
            charset = "latin"
            """)
        #expect(config.text.decodeEffect.charset == [.latin])
    }

    @Test("array charset decodes as set")
    func arrayCharset() throws {
        let config = try decode(
            """
            [text.decode_effect]
            charset = ["latin", "cjk"]
            """)
        #expect(config.text.decodeEffect.charset == [.latin, .cjk])
    }

    @Test("unspecified charset defaults to all cases")
    func defaultCharset() throws {
        let config = try decode("")
        #expect(config.text.decodeEffect.charset == Set(CharsetName.allCases))
    }
}

// MARK: - Invariants

@Suite("Invariants")
struct InvariantTests {
    @Test("all TextConfig fields are non-optional after decode")
    func textFieldsNonOptional() throws {
        let config = try decode("")
        // These are compile-time guarantees (non-optional types),
        // but verify they have meaningful values
        #expect(!config.text.default.fontName.isEmpty)
        #expect(!config.text.title.fontName.isEmpty)
        #expect(!config.text.artist.fontName.isEmpty)
        #expect(!config.text.lyric.fontName.isEmpty)
        #expect(!config.text.highlight.fontName.isEmpty)
        #expect(config.text.default.fontSize > 0)
        #expect(config.text.title.fontSize > 0)
    }

    @Test("highlight inherits from lyric chain, not default directly")
    func highlightInheritancePath() throws {
        let config = try decode(
            """
            [text.lyric]
            font = "Special Lyric Font"
            """)
        // highlight should get lyric's font, proving it inherits from lyric
        #expect(config.text.highlight.fontName == "Special Lyric Font")
        // but default should still be the default
        #expect(config.text.default.fontName == "Helvetica Neue")
    }
}

// MARK: - Silent fallback design

@Suite("Silent fallback on decode error")
struct SilentFallbackTests {
    @Test("load() returns nil for invalid TOML content")
    func decodeReturnsNilForGarbage() {
        let ds = ConfigDataSourceImpl()
        let result = ds.decode(content: "{{{{not valid TOML at all!!", path: "test.toml", configDir: "/tmp")
        #expect(result == nil)
    }

    @Test("tryDecode throws for invalid config content")
    func decodeOrThrowThrowsForGarbage() {
        let ds = ConfigDataSourceImpl()
        #expect(throws: (any Error).self) {
            try ds.decodeOrThrow(content: "{{{{not valid TOML at all!!", path: "test.toml", configDir: "/tmp")
        }
    }
}

// MARK: - RippleShape polymorphic decoding

@Suite("RippleShape polymorphic decoding")
struct RippleShapeDecodingTests {
    @Test("absent shape defaults to circle")
    func defaultShape() throws {
        let config = try decode("")
        #expect(config.ripple.shape == .circle)
    }

    @Test("missing shape under existing [ripple] still defaults to circle")
    func partialRippleDefaultsShape() throws {
        let config = try decode(
            """
            [ripple]
            color = "#FF0000FF"
            """)
        #expect(config.ripple.shape == .circle)
    }

    @Test("bare string \"circle\" decodes as circle")
    func bareCircle() throws {
        let config = try decode(
            """
            [ripple]
            shape = "circle"
            """)
        #expect(config.ripple.shape == .circle)
    }

    @Test("polygon table decodes with sides and angle")
    func polygonTable() throws {
        let config = try decode(
            """
            [ripple.shape]
            type = "polygon"
            sides = 6
            angle = 15
            """)
        #expect(config.ripple.shape == .polygon(sides: 6, angle: 15))
    }

    @Test("polygon without angle defaults angle to 0")
    func polygonNoAngle() throws {
        let config = try decode(
            """
            [ripple.shape]
            type = "polygon"
            sides = 5
            """)
        #expect(config.ripple.shape == .polygon(sides: 5, angle: 0))
    }

    @Test("polygon with sides < minimum throws dataCorrupted citing sides")
    func polygonSidesTooSmallThrows() {
        do {
            _ = try decode(
                """
                [ripple.shape]
                type = "polygon"
                sides = 2
                """)
            Issue.record("Expected DecodingError.dataCorrupted")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("sides"))
        } catch {
            Issue.record("Expected DecodingError.dataCorrupted, got \(error)")
        }
    }

    @Test("polygon with sides > maximum throws dataCorrupted citing sides")
    func polygonSidesTooLargeThrows() {
        do {
            _ = try decode(
                """
                [ripple.shape]
                type = "polygon"
                sides = 9999
                """)
            Issue.record("Expected DecodingError.dataCorrupted")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("sides"))
        } catch {
            Issue.record("Expected DecodingError.dataCorrupted, got \(error)")
        }
    }

    @Test("polygon at boundary sides = 3 decodes")
    func polygonMinimumSides() throws {
        let config = try decode(
            """
            [ripple.shape]
            type = "polygon"
            sides = 3
            """)
        #expect(config.ripple.shape == .polygon(sides: 3, angle: 0))
    }

    @Test("polygon at boundary sides = 256 decodes")
    func polygonMaximumSides() throws {
        let config = try decode(
            """
            [ripple.shape]
            type = "polygon"
            sides = 256
            """)
        #expect(config.ripple.shape == .polygon(sides: 256, angle: 0))
    }

    @Test("polygon angle accepts integer literal")
    func polygonIntegerAngle() throws {
        let config = try decode(
            """
            [ripple.shape]
            type = "polygon"
            sides = 6
            angle = 30
            """)
        #expect(config.ripple.shape == .polygon(sides: 6, angle: 30))
    }

    @Test("unknown shape type throws")
    func unknownShape() {
        #expect(throws: DecodingError.self) {
            _ = try decode(
                """
                [ripple.shape]
                type = "blob"
                """)
        }
    }

    @Test("bare \"polygon\" requires table form (lacks sides)")
    func barePolygonRequiresTable() {
        #expect(throws: DecodingError.self) {
            _ = try decode(
                """
                [ripple]
                shape = "polygon"
                """)
        }
    }

    @Test("bare string with unknown name throws")
    func bareUnknownNameThrows() {
        #expect(throws: DecodingError.self) {
            _ = try decode(
                """
                [ripple]
                shape = "wibble"
                """)
        }
    }

    @Test("polygon encode roundtrip preserves sides and angle")
    func polygonEncodeRoundtrip() throws {
        let original = RippleShape.polygon(sides: 7, angle: 22.5)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RippleShape.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("circle encode emits type field")
    func circleEncode() throws {
        let encoded = try JSONEncoder().encode(RippleShape.circle)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains("\"type\""))
        #expect(json.contains("\"circle\""))
    }
}

// MARK: - Spectrum config (TOML)

@Suite("Spectrum TOML decoding")
struct SpectrumTomlDecodingTests {
    @Test("missing [spectrum] section uses defaults (disabled)")
    func noSection() throws {
        let config = try decode("")
        #expect(config.spectrum.enabled == false)
        #expect(config.spectrum.stereo == true)
        #expect(
            config.spectrum.barColor
                == .gradient(["#060912B3", "#20407FB3", "#3E86F0B3", "#9C6CEEB3", "#F4F1FFB3"]))
        #expect(config.spectrum.gradientDirection == .level)
        #expect(config.spectrum.backgroundColor == nil)
        #expect(config.spectrum.barWidth.value == 6)
        #expect(config.spectrum.barSpacing.value == 4)
        #expect(config.spectrum.minFreq.value == 40)
        #expect(config.spectrum.maxFreq.value == 14000)
        #expect(config.spectrum.minDb.value == -60)
        #expect(config.spectrum.maxDb.value == 0)
        #expect(config.spectrum.scale == .linear)
        #expect(config.spectrum.noiseReduction.value == 77)
        #expect(config.spectrum.fftSize.value == 1024)
        #expect(config.spectrum.placement == .bottom)
        #expect(config.spectrum.heightRatio.value == 0.25)
        // The absolute clamp is unset by default (pure ratio).
        #expect(config.spectrum.minHeight == nil)
        #expect(config.spectrum.maxHeight == nil)
        // Fully opaque by default; corner radius derives from bar_width.
        #expect(config.spectrum.barOpacity.value == 1)
        #expect(config.spectrum.barCornerRadius == nil)
    }

    @Test("min_height / max_height decode into the optional clamp")
    func heightClampDecodes() throws {
        let config = try decode(
            """
            [spectrum]
            min_height = 24
            max_height = 320
            """)
        #expect(config.spectrum.minHeight?.value == 24)
        #expect(config.spectrum.maxHeight?.value == 320)
    }

    @Test("full [spectrum] section decodes every field")
    func fullSection() throws {
        let config = try decode(
            """
            [spectrum]
            enabled = true
            stereo = false
            bar_width = 12
            bar_spacing = 6
            bar_color = "#FF8800"
            gradient_direction = "level"
            background_color = "#00000080"
            min_freq = 60
            max_freq = 12000
            min_db = -60
            max_db = -10
            scale = "db"
            noise_reduction = 85
            fft_size = 2048
            placement = "underlay"
            height_ratio = 0.5
            bar_opacity = 0.5
            bar_corner_radius = 4
            """)
        #expect(config.spectrum.enabled == true)
        #expect(config.spectrum.stereo == false)
        #expect(config.spectrum.barWidth.value == 12)
        #expect(config.spectrum.barSpacing.value == 6)
        #expect(config.spectrum.barColor == .solid("#FF8800"))
        #expect(config.spectrum.gradientDirection == .level)
        #expect(config.spectrum.backgroundColor == ColorConfig(hex: "#00000080"))
        #expect(config.spectrum.minFreq.value == 60)
        #expect(config.spectrum.maxFreq.value == 12000)
        #expect(config.spectrum.minDb.value == -60)
        #expect(config.spectrum.maxDb.value == -10)
        #expect(config.spectrum.scale == .db)
        #expect(config.spectrum.noiseReduction.value == 85)
        #expect(config.spectrum.fftSize.value == 2048)
        #expect(config.spectrum.placement == .underlay)
        #expect(config.spectrum.heightRatio.value == 0.5)
        #expect(config.spectrum.barOpacity.value == 0.5)
        #expect(config.spectrum.barCornerRadius?.value == 4)
    }

    @Test("gradient bar_color decodes from an array")
    func gradientBarColor() throws {
        let config = try decode(
            """
            [spectrum]
            bar_color = ["#FF0000", "#00FF00", "#0000FF"]
            """)
        #expect(config.spectrum.barColor == .gradient(["#FF0000", "#00FF00", "#0000FF"]))
    }

    @Test("partial section keeps defaults for omitted keys")
    func partialSection() throws {
        let config = try decode(
            """
            [spectrum]
            enabled = true
            """)
        #expect(config.spectrum.enabled == true)
        #expect(config.spectrum.barWidth.value == 6)
        #expect(config.spectrum.placement == .bottom)
        #expect(config.spectrum.fftSize.value == 1024)
    }

    @Test("unknown placement throws")
    func unknownPlacementThrows() {
        #expect(throws: DecodingError.self) {
            _ = try decode(
                """
                [spectrum]
                placement = "sideways"
                """)
        }
    }
}

// MARK: - Lyrics config (TOML)

@Suite("Lyrics TOML decoding")
struct LyricsTomlDecodingTests {
    @Test("fallback_command and timeout_ms both specified")
    func fullySpecified() throws {
        let config = try decode(
            """
            [lyrics]
            fallback_command = ["/usr/bin/python3", "/path/to/script.py"]
            timeout_ms = 8000
            """)
        // Expected value built via the memberwise init, so this also pins that public API.
        #expect(
            config.lyrics == LyricsConfig(fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"], timeoutMs: 8000))
    }

    @Test("timeout_ms omitted defaults to 5000")
    func timeoutDefaultsTo5000() throws {
        let config = try decode(
            """
            [lyrics]
            fallback_command = ["/usr/bin/python3", "/path/to/script.py"]
            """)
        #expect(config.lyrics?.fallbackCommand == ["/usr/bin/python3", "/path/to/script.py"])
        #expect(config.lyrics?.timeoutMs.value == 5000)
    }

    @Test("fallback_command omitted defaults to empty array")
    func fallbackCommandDefaultsToEmpty() throws {
        let config = try decode(
            """
            [lyrics]
            timeout_ms = 3000
            """)
        #expect(config.lyrics?.fallbackCommand == [])
        #expect(config.lyrics?.timeoutMs.value == 3000)
    }
}
