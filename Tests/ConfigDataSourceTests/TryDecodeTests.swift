import Files
import Foundation
import Testing

@testable import ConfigDataSource

@Suite("tryDecode")
struct TryDecodeTests {
    // Inject the config root via `ConfigDataSourceImpl(configHome:)` instead of mutating
    // the process-global `XDG_CONFIG_HOME` with `setenv` (forbidden by the repo Testing
    // Rules — it races under parallel Swift Testing). `content == nil` leaves the root
    // empty so no config file is discovered.
    private func dataSource(withConfig content: String?) throws -> (ConfigDataSourceImpl, Folder) {
        let xdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        if let content {
            let lyraDir = try xdgConfig.createSubfolder(named: "lyra")
            try lyraDir.createFile(named: "config.toml").write(content)
        }
        return (ConfigDataSourceImpl(configHome: xdgConfig.path), xdgConfig)
    }

    @Test("returns empty string when no config file exists")
    func noFile() throws {
        let (ds, folder) = try dataSource(withConfig: nil)
        defer { try? folder.delete() }

        let result = try ds.tryDecode(strictOptionalSections: true)
        #expect(result == "")
    }

    @Test("returns path when valid TOML config exists")
    func validToml() throws {
        let (ds, folder) = try dataSource(withConfig: "")
        defer { try? folder.delete() }

        let result = try ds.tryDecode(strictOptionalSections: true)
        #expect(result.hasSuffix("config.toml"))
    }

    @Test("throws on invalid TOML content")
    func invalidToml() throws {
        let (ds, folder) = try dataSource(withConfig: "{{invalid")
        defer { try? folder.delete() }

        #expect(throws: (any Error).self) { try ds.tryDecode(strictOptionalSections: true) }
    }
}
