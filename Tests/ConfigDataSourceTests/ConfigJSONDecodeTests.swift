import Domain
import Foundation
import Testing

@testable import ConfigDataSource

@Suite("ConfigDataSource JSON decoding and nested include merge")
struct ConfigJSONDecodeTests {
    private let dataSource = ConfigDataSourceImpl()

    @Test("decodes a JSON config via the .json branch of decodeOrThrow")
    func decodesJSONConfig() throws {
        // The template is the canonical serialized AppConfig.defaults, so it is
        // guaranteed decodable — and a `.json` path routes through the JSONDecoder
        // branch rather than the TOML one.
        let json = try #require(dataSource.template(format: .json))
        let config = try dataSource.decodeOrThrow(content: json, path: "/tmp/config.json", configDir: "/tmp")
        #expect(config.screen == AppConfig.defaults.screen)
    }

    @Test("strictly probes optional sections from a JSON config")
    func strictProbesJSONOptionalSections() throws {
        // Reaches strictDecodeOptionalSections' JSON branch: a well-formed config
        // returns without throwing (a malformed [ai]/[lyrics] would throw here).
        let json = try #require(dataSource.template(format: .json))
        try dataSource.strictDecodeOptionalSections(content: json, path: "/tmp/config.json", configDir: "/tmp")
    }

    @Test("deep-merges nested tables shared between main and an included file")
    func deepMergesNestedTables() throws {
        let tempDir = NSTemporaryDirectory() + "lyra-config-merge-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        try """
        [text.artist]
        size = 14
        """.write(toFile: tempDir + "/extra.toml", atomically: true, encoding: .utf8)

        // Both main and the include define sub-tables under [text], so resolving the
        // include recurses through deepMerge into the shared `text` table.
        let mainToml = """
            includes = ["extra.toml"]
            [text.title]
            size = 20
            """
        let merged = try dataSource.preparedTomlTable(content: mainToml, configDir: tempDir)
        let textTable = try #require(merged["text"]?.table)
        #expect(textTable["title"]?.table != nil)
        #expect(textTable["artist"]?.table != nil)
    }
}
