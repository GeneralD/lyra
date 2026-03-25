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
        #expect(config.wallpaper?.location == "loop.mp4")
        #expect(config.wallpaper?.start == nil)
        #expect(config.wallpaper?.end == nil)
    }

    @Test("[wallpaper] table with location only")
    func tableLocationOnly() throws {
        let config = try decode(
            """
            [wallpaper]
            location = "bg.mp4"
            """)
        #expect(config.wallpaper?.location == "bg.mp4")
        #expect(config.wallpaper?.start == nil)
        #expect(config.wallpaper?.end == nil)
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
        #expect(config.wallpaper?.location == "https://www.youtube.com/watch?v=XXXXX")
        #expect(config.wallpaper?.start == 30.0)
        #expect(config.wallpaper?.end == 225.0)
    }

    @Test("[wallpaper] table with start only")
    func tableStartOnly() throws {
        let config = try decode(
            """
            [wallpaper]
            location = "video.mp4"
            start = "1:00"
            """)
        #expect(config.wallpaper?.start == 60.0)
        #expect(config.wallpaper?.end == nil)
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
        #expect(config.wallpaper?.start == 120.0)
        #expect(config.wallpaper?.end == nil)
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
