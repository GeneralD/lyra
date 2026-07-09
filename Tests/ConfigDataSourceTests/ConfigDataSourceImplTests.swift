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

        #expect(!dataSource.configDir.isEmpty)
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
