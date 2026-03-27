import Entity
import Foundation
import RegexBuilder
import Testing

@testable import ConfigDataSource

// Snapshot Testing Strategy
//
// These tests compare template output as full strings to catch any unintended change.
// However, `DecodeEffectConfig.charset` is a Set<CharsetName>, whose iteration order
// is non-deterministic. This means the charset array in TOML/JSON output can appear
// in any order across runs.
//
// To handle this:
// 1. Extract the charset values via Regex
// 2. Replace the charset portion with a placeholder
// 3. Compare the rest of the output as an exact string match
// 4. Compare charset values as a Set (order-independent)
//
// Alternatives considered:
// - Embedding charset as a regex pattern (e.g. `#/charset = \[.*\]/#`) in a multiline
//   regex literal covering the entire expected output. This would avoid the placeholder,
//   but TOML/JSON contain many regex-special characters (`[`, `.`, `{`) requiring
//   extensive escaping, making the expected value far less readable than plain text.

private let charsetPlaceholder = "__CHARSET__"

@Suite("ConfigDataSource.template")
struct ConfigTemplateTests {
    let dataSource = ConfigDataSourceImpl()

    // MARK: - TOML snapshot

    @Test("TOML template matches snapshot")
    func tomlSnapshot() {
        let toml = dataSource.template(format: .toml)!

        // TOML charset: charset = [ 'latin', 'greek', ... ]
        let charsetRegex = Regex {
            "charset = [ "
            Capture(OneOrMore(.reluctant) { /.*/ })
            " ]"
        }
        let charsetMatch = toml.firstMatch(of: charsetRegex)!
        let charsetValues = String(charsetMatch.output.1)
            .components(separatedBy: "', '")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
        #expect(Set(charsetValues) == Set(CharsetName.allCases.map(\.rawValue)))

        let normalized = toml.replacing(charsetRegex, with: "charset = \(charsetPlaceholder)")

        // swift-format-ignore
        let expected = """
screen = 'main'

[artwork]
opacity = 1.0
size = 96.0

[ripple]
color = '#AAAAFFFF'
duration = 0.6
enabled = true
idle = 1.0
radius = 60.0

[text.artist]
color = '#FFFFFFD9'
fontName = 'Helvetica Neue'
fontSize = 12.0
fontWeight = 'medium'
shadow = '#000000E6'
spacing = 6.0

[text.decode_effect]
charset = \(charsetPlaceholder)
duration = 0.8

[text.default]
color = '#FFFFFFD9'
fontName = 'Helvetica Neue'
fontSize = 12.0
fontWeight = 'regular'
shadow = '#000000E6'
spacing = 6.0

[text.highlight]
color = [ '#B8942DFF', '#EDCF73FF', '#FFEB99FF', '#CCA64DFF', '#A68038FF' ]
fontName = 'Helvetica Neue'
fontSize = 12.0
fontWeight = 'regular'
shadow = '#000000E6'
spacing = 6.0

[text.lyric]
color = '#FFFFFFD9'
fontName = 'Helvetica Neue'
fontSize = 12.0
fontWeight = 'regular'
shadow = '#000000E6'
spacing = 6.0

[text.title]
color = '#FFFFFFD9'
fontName = 'Helvetica Neue'
fontSize = 18.0
fontWeight = 'bold'
shadow = '#000000E6'
spacing = 6.0
"""

        #expect(normalized.trimmingCharacters(in: .newlines) == expected)
    }

    // MARK: - JSON snapshot

    @Test("JSON template matches snapshot")
    func jsonSnapshot() {
        let json = dataSource.template(format: .json)!

        // JSON charset: "charset" : [\n    "latin",\n    "greek",\n    ... \n  ]
        let charsetRegex = Regex {
            "\"charset\" : "
            Capture {
                "["
                OneOrMore(.any, .reluctant)
                "]"
            }
        }
        .dotMatchesNewlines()

        let charsetMatch = json.firstMatch(of: charsetRegex)!
        let inner = String(charsetMatch.output.1)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let charsetValues = inner.components(separatedBy: ",").compactMap { item -> String? in
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return trimmed.isEmpty ? nil : trimmed
        }
        #expect(Set(charsetValues) == Set(CharsetName.allCases.map(\.rawValue)))

        let normalized = json.replacing(charsetRegex, with: "\"charset\" : \"\(charsetPlaceholder)\"")

        // swift-format-ignore
        let expected = """
{
  "artwork" : {
    "opacity" : 1,
    "size" : 96
  },
  "ripple" : {
    "color" : "#AAAAFFFF",
    "duration" : 0.6,
    "enabled" : true,
    "idle" : 1,
    "radius" : 60
  },
  "screen" : "main",
  "text" : {
    "artist" : {
      "color" : "#FFFFFFD9",
      "fontName" : "Helvetica Neue",
      "fontSize" : 12,
      "fontWeight" : "medium",
      "shadow" : "#000000E6",
      "spacing" : 6
    },
    "decode_effect" : {
      "charset" : "\(charsetPlaceholder)",
      "duration" : 0.8
    },
    "default" : {
      "color" : "#FFFFFFD9",
      "fontName" : "Helvetica Neue",
      "fontSize" : 12,
      "fontWeight" : "regular",
      "shadow" : "#000000E6",
      "spacing" : 6
    },
    "highlight" : {
      "color" : [
        "#B8942DFF",
        "#EDCF73FF",
        "#FFEB99FF",
        "#CCA64DFF",
        "#A68038FF"
      ],
      "fontName" : "Helvetica Neue",
      "fontSize" : 12,
      "fontWeight" : "regular",
      "shadow" : "#000000E6",
      "spacing" : 6
    },
    "lyric" : {
      "color" : "#FFFFFFD9",
      "fontName" : "Helvetica Neue",
      "fontSize" : 12,
      "fontWeight" : "regular",
      "shadow" : "#000000E6",
      "spacing" : 6
    },
    "title" : {
      "color" : "#FFFFFFD9",
      "fontName" : "Helvetica Neue",
      "fontSize" : 18,
      "fontWeight" : "bold",
      "shadow" : "#000000E6",
      "spacing" : 6
    }
  }
}
"""

        #expect(normalized == expected)
    }

    // MARK: - JSON round-trip

    @Test("JSON template decodes back to AppConfig with correct values")
    func jsonRoundTrip() throws {
        let json = dataSource.template(format: .json)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json.data(using: .utf8)!)
        #expect(decoded.screen == .main)
        #expect(decoded.artwork.size.value == 96)
        #expect(decoded.artwork.opacity.value == 1.0)
        #expect(decoded.ripple.enabled == true)
        #expect(decoded.ripple.color == "#AAAAFFFF")
        #expect(decoded.text.title.fontSize == 18)
        #expect(decoded.text.title.fontWeight == "bold")
        #expect(decoded.text.artist.fontWeight == "medium")
        #expect(
            decoded.text.highlight.color
                == .gradient(["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"]))
        #expect(decoded.text.decodeEffect.charset == Set(CharsetName.allCases))
        #expect(decoded.ai == nil)
        #expect(decoded.wallpaper == nil)
    }
}
