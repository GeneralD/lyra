import Files
import Foundation
import Testing

@testable import ConfigDataSource

@Suite("ConfigDataSourceImpl.configDir")
struct ConfigDataSourceImplConfigDirTests {
    @Test("configDir falls back to home directory when no config file exists")
    func fallsBackToHomeWhenMissing() throws {
        let emptyXdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        defer { try? emptyXdgConfig.delete() }

        let dataSource = ConfigDataSourceImpl(configHome: emptyXdgConfig.path)

        #expect(dataSource.configDir == Folder.home.path)
    }

    @Test("configDir matches the discovered config file's parent directory")
    func matchesDiscoveredConfigParent() throws {
        let xdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        defer { try? xdgConfig.delete() }

        let lyraDir = try xdgConfig.createSubfolder(named: "lyra")
        try lyraDir.createFile(named: "config.toml").write("screen = \"main\"")

        let dataSource = ConfigDataSourceImpl(configHome: xdgConfig.path)

        #expect(dataSource.configDir == lyraDir.path)
    }
}

@Suite("ConfigDataSourceImpl.tryDecode — strict optional-section validation")
struct ConfigDataSourceImplTryDecodeTests {
    private func dataSource(withConfig content: String) throws -> (ConfigDataSourceImpl, Folder) {
        let xdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        let lyraDir = try xdgConfig.createSubfolder(named: "lyra")
        try lyraDir.createFile(named: "config.toml").write(content)
        return (ConfigDataSourceImpl(configHome: xdgConfig.path), xdgConfig)
    }

    @Test("a malformed [lyrics] section fails validation instead of passing silently")
    func malformedLyricsSectionFailsValidation() throws {
        let (dataSource, folder) = try dataSource(
            withConfig: """
                screen = "main"

                [lyrics]
                fallback_command = "/not/an/argv/array"
                """)
        defer { try? folder.delete() }

        #expect(throws: (any Error).self) { try dataSource.tryDecode() }
    }

    @Test("a malformed [lyrics] section still loads leniently — the rest of the config survives")
    func malformedLyricsSectionLoadsLeniently() throws {
        let (dataSource, folder) = try dataSource(
            withConfig: """
                screen = "main"

                [lyrics]
                fallback_command = "/not/an/argv/array"
                """)
        defer { try? folder.delete() }

        let loaded = dataSource.load()
        #expect(loaded != nil)
        #expect(loaded?.config.lyrics == nil)
        #expect(loaded?.config.screen == .main)
    }

    @Test("a well-formed [lyrics] section passes validation")
    func wellFormedLyricsSectionPassesValidation() throws {
        let (dataSource, folder) = try dataSource(
            withConfig: """
                screen = "main"

                [lyrics]
                fallback_command = ["/usr/bin/python3", "/path/to/script.py"]
                timeout_ms = 5000
                """)
        defer { try? folder.delete() }

        #expect(throws: Never.self) { try dataSource.tryDecode() }
    }
}
