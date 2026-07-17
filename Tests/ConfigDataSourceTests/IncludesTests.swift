import Domain
import Foundation
import Testing

@testable import ConfigDataSource

@Suite("Config includes")
struct IncludesTests {
    private let tempDir: String = NSTemporaryDirectory() + "lyra-config-test-\(UUID().uuidString)"
    private let dataSource = ConfigDataSourceImpl()

    private func setUp(mainToml: String, files: [String: String] = [:]) throws -> String {
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let mainPath = tempDir + "/config.toml"
        try mainToml.write(toFile: mainPath, atomically: true, encoding: .utf8)
        for (name, content) in files {
            try content.write(toFile: tempDir + "/\(name)", atomically: true, encoding: .utf8)
        }
        return mainPath
    }

    private func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    @Test("loads AI config from included file")
    func aiConfigFromInclude() throws {
        defer { tearDown() }

        let mainPath = try setUp(
            mainToml: """
                includes = ["ai.toml"]
                screen = "main"
                """,
            files: [
                "ai.toml": """
                [ai]
                endpoint = "https://example.com/v1"
                model = "test-model"
                api_key = "test-key"
                """
            ]
        )

        let content = try String(contentsOfFile: mainPath, encoding: .utf8)
        let config = dataSource.decode(content: content, path: mainPath, configDir: tempDir)
        #expect(config?.ai != nil)
        #expect(config?.ai?.endpoint == "https://example.com/v1")
        #expect(config?.ai?.model == "test-model")
        #expect(config?.ai?.apiKey == "test-key")
    }

    @Test("main config takes precedence over included")
    func mainOverridesInclude() throws {
        defer { tearDown() }

        let mainPath = try setUp(
            mainToml: """
                includes = ["base.toml"]
                screen = "match"
                """,
            files: [
                "base.toml": """
                screen = "main"
                """
            ]
        )

        let content = try String(contentsOfFile: mainPath, encoding: .utf8)
        let config = dataSource.decode(content: content, path: mainPath, configDir: tempDir)
        #expect(config?.screen == ScreenSelector.main)
    }

    @Test("no includes section works fine")
    func noIncludes() throws {
        defer { tearDown() }

        let mainPath = try setUp(
            mainToml: """
                screen = "main"
                """)

        let content = try String(contentsOfFile: mainPath, encoding: .utf8)
        let config = dataSource.decode(content: content, path: mainPath, configDir: tempDir)
        #expect(config?.screen == ScreenSelector.main)
        #expect(config?.ai == nil)
    }

    @Test("includedConfigPaths resolves relative and absolute includes, skipping missing files")
    func includedConfigPathsResolution() throws {
        defer { tearDown() }

        let lyraDir = tempDir + "/lyra"
        let outsideDir = tempDir + "/outside"
        try FileManager.default.createDirectory(atPath: lyraDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: outsideDir, withIntermediateDirectories: true)
        try "screen = \"main\"".write(toFile: lyraDir + "/koko.toml", atomically: true, encoding: .utf8)
        try "screen = \"main\"".write(toFile: outsideDir + "/shared.toml", atomically: true, encoding: .utf8)
        try """
            includes = ["koko.toml", "\(outsideDir)/shared.toml", "missing.toml"]
            """.write(toFile: lyraDir + "/config.toml", atomically: true, encoding: .utf8)

        // tempDir acts as $XDG_CONFIG_HOME, so findConfigFile resolves <tempDir>/lyra/config.toml.
        let paths = ConfigDataSourceImpl(configHome: tempDir).includedConfigPaths

        // Compare by suffix: the Files library canonicalizes /var/... to /private/var/...
        #expect(paths.count == 2)
        #expect(paths.contains { $0.hasSuffix("/lyra/koko.toml") })
        #expect(paths.contains { $0.hasSuffix("/outside/shared.toml") })
    }

    @Test("includedConfigPaths is empty for a JSON config (includes is TOML-only)")
    func includedConfigPathsEmptyForJson() throws {
        defer { tearDown() }

        let lyraDir = tempDir + "/lyra"
        try FileManager.default.createDirectory(atPath: lyraDir, withIntermediateDirectories: true)
        try "{\"screen\": \"main\"}".write(toFile: lyraDir + "/config.json", atomically: true, encoding: .utf8)

        #expect(ConfigDataSourceImpl(configHome: tempDir).includedConfigPaths.isEmpty)
    }
}
