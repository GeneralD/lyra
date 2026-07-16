import Files
import Foundation
import Testing

@testable import ConfigDataSource

@Suite("ConfigDataSourceImpl.configDir")
struct ConfigDataSourceImplConfigDirTests {
    @Test("configDir points at the expected config dir (not home) when no config file exists (#329)")
    func fallsBackToExpectedDirWhenMissing() throws {
        let emptyXdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        defer { try? emptyXdgConfig.delete() }

        let dataSource = ConfigDataSourceImpl(configHome: emptyXdgConfig.path)

        // Not home — the watcher must arm on where the file *would* be created so a
        // config added after daemon start is picked up without a restart (#329).
        #expect(dataSource.configDir != Folder.home.path)
        #expect(dataSource.configDir.hasSuffix("/lyra"))
        #expect(dataSource.configDir.hasPrefix(emptyXdgConfig.path))
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

@Suite("ConfigDataSourceImpl.tryDecode — optional-section strictness (#330)")
struct ConfigDataSourceImplTryDecodeTests {
    private func dataSource(withConfig content: String) throws -> (ConfigDataSourceImpl, Folder) {
        let xdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        let lyraDir = try xdgConfig.createSubfolder(named: "lyra")
        try lyraDir.createFile(named: "config.toml").write(content)
        return (ConfigDataSourceImpl(configHome: xdgConfig.path), xdgConfig)
    }

    private let malformedLyrics = """
        screen = "main"

        [lyrics]
        fallback_command = "/not/an/argv/array"
        """

    private let malformedAI = """
        screen = "main"

        [ai]
        endpoint = ["not", "a", "string"]
        """

    @Test("strict mode surfaces a malformed [lyrics] section as a failure (healthcheck)")
    func malformedLyricsSectionFailsStrictValidation() throws {
        let (dataSource, folder) = try dataSource(withConfig: malformedLyrics)
        defer { try? folder.delete() }

        #expect(throws: (any Error).self) { try dataSource.tryDecode(strictOptionalSections: true) }
    }

    @Test("lenient mode tolerates a malformed [lyrics] section — degrades like startup (hot-reload)")
    func malformedLyricsSectionPassesLenientValidation() throws {
        let (dataSource, folder) = try dataSource(withConfig: malformedLyrics)
        defer { try? folder.delete() }

        #expect(throws: Never.self) { try dataSource.tryDecode(strictOptionalSections: false) }
    }

    @Test("a malformed [lyrics] section still loads leniently — the rest of the config survives")
    func malformedLyricsSectionLoadsLeniently() throws {
        let (dataSource, folder) = try dataSource(withConfig: malformedLyrics)
        defer { try? folder.delete() }

        let loaded = dataSource.load()
        #expect(loaded != nil)
        #expect(loaded?.config.lyrics == nil)
        #expect(loaded?.config.screen == .main)
    }

    @Test("strict mode surfaces a malformed [ai] section as a failure (healthcheck)")
    func malformedAISectionFailsStrictValidation() throws {
        let (dataSource, folder) = try dataSource(withConfig: malformedAI)
        defer { try? folder.delete() }

        #expect(throws: (any Error).self) { try dataSource.tryDecode(strictOptionalSections: true) }
    }

    @Test("lenient mode tolerates a malformed [ai] section — degrades like startup (hot-reload)")
    func malformedAISectionPassesLenientValidation() throws {
        let (dataSource, folder) = try dataSource(withConfig: malformedAI)
        defer { try? folder.delete() }

        #expect(throws: Never.self) { try dataSource.tryDecode(strictOptionalSections: false) }
    }

    @Test("a well-formed [lyrics] section passes in both modes")
    func wellFormedLyricsSectionPassesBothModes() throws {
        let (dataSource, folder) = try dataSource(
            withConfig: """
                screen = "main"

                [lyrics]
                fallback_command = ["/usr/bin/python3", "/path/to/script.py"]
                timeout_ms = 5000
                """)
        defer { try? folder.delete() }

        #expect(throws: Never.self) { try dataSource.tryDecode(strictOptionalSections: true) }
        #expect(throws: Never.self) { try dataSource.tryDecode(strictOptionalSections: false) }
    }

    @Test("a malformed required structure fails even in lenient mode — the required decode always gates")
    func malformedRequiredStructureFailsEvenInLenientMode() throws {
        // `wallpaper = [` is an unterminated array: the required decode itself
        // fails, so lenient mode cannot rescue it (unlike an optional-section error).
        let (dataSource, folder) = try dataSource(withConfig: "wallpaper = [")
        defer { try? folder.delete() }

        #expect(throws: (any Error).self) { try dataSource.tryDecode(strictOptionalSections: false) }
        #expect(throws: (any Error).self) { try dataSource.tryDecode(strictOptionalSections: true) }
    }

    @Test("a malformed [developer] section fails validation instead of silently disabling the trace")
    func malformedDeveloperSectionFailsValidation() throws {
        let (dataSource, folder) = try dataSource(
            withConfig: """
                screen = "main"

                [developer]
                lyrics_resolution = "true"
                """)
        defer { try? folder.delete() }

        #expect(throws: (any Error).self) { try dataSource.tryDecode(strictOptionalSections: true) }
    }

    @Test("a malformed [developer] section still loads leniently — the rest of the config survives")
    func malformedDeveloperSectionLoadsLeniently() throws {
        let (dataSource, folder) = try dataSource(
            withConfig: """
                screen = "main"

                [developer]
                lyrics_resolution = "true"
                """)
        defer { try? folder.delete() }

        let loaded = dataSource.load()
        #expect(loaded != nil)
        #expect(loaded?.config.developer == nil)
        #expect(loaded?.config.screen == .main)
    }

    @Test("a well-formed [developer] section passes validation")
    func wellFormedDeveloperSectionPassesValidation() throws {
        let (dataSource, folder) = try dataSource(
            withConfig: """
                screen = "main"

                [developer]
                lyrics_resolution = true
                """)
        defer { try? folder.delete() }

        #expect(throws: Never.self) { try dataSource.tryDecode(strictOptionalSections: true) }
    }
}
