import Foundation
import Testing

@testable import ConfigDataSource

@Suite("tryDecode", .serialized)
struct TryDecodeTests {
    @Test("returns empty string when no config file exists")
    func noFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer { unsetenv("XDG_CONFIG_HOME") }

        let ds = ConfigDataSourceImpl()
        let result = try ds.tryDecode()
        #expect(result == "")
    }

    @Test("returns path when valid TOML config exists")
    func validToml() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let lyraDir = "\(tmp)/lyra"
        try FileManager.default.createDirectory(atPath: lyraDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Write minimal valid TOML
        try "".write(toFile: "\(lyraDir)/config.toml", atomically: true, encoding: .utf8)

        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer { unsetenv("XDG_CONFIG_HOME") }

        let ds = ConfigDataSourceImpl()
        let result = try ds.tryDecode()
        #expect(result.hasSuffix("config.toml"))
    }

    @Test("throws on invalid TOML content")
    func invalidToml() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let lyraDir = "\(tmp)/lyra"
        try FileManager.default.createDirectory(atPath: lyraDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        try "{{invalid".write(toFile: "\(lyraDir)/config.toml", atomically: true, encoding: .utf8)

        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer { unsetenv("XDG_CONFIG_HOME") }

        let ds = ConfigDataSourceImpl()
        #expect(throws: (any Error).self) { try ds.tryDecode() }
    }
}
