// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Entity
import Foundation
import Testing

@testable import ConfigDataSource

@Suite("ConfigDataSource.writeTemplate", .serialized)
struct ConfigWriteTemplateTests {
    @Test("writes TOML template to XDG_CONFIG_HOME/lyra/config.toml")
    func writesToml() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer {
            unsetenv("XDG_CONFIG_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }

        let ds = ConfigDataSourceImpl()
        let path = try ds.writeTemplate(format: .toml, force: false)

        #expect(path == "\(tmp)/lyra/config.toml")
        #expect(FileManager.default.fileExists(atPath: path))

        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content == ds.template(format: .toml))
    }

    @Test("writes JSON template to XDG_CONFIG_HOME/lyra/config.json")
    func writesJson() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer {
            unsetenv("XDG_CONFIG_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }

        let ds = ConfigDataSourceImpl()
        let path = try ds.writeTemplate(format: .json, force: false)

        #expect(path == "\(tmp)/lyra/config.json")
        #expect(FileManager.default.fileExists(atPath: path))

        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content == ds.template(format: .json))
    }

    @Test("throws alreadyExists when file exists and force is false")
    func throwsWhenExists() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer {
            unsetenv("XDG_CONFIG_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }

        let ds = ConfigDataSourceImpl()
        _ = try ds.writeTemplate(format: .toml, force: false)

        #expect(throws: ConfigWriteError.self) {
            try ds.writeTemplate(format: .toml, force: false)
        }
    }

    @Test("force overwrites existing file")
    func forceOverwrites() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer {
            unsetenv("XDG_CONFIG_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }

        let ds = ConfigDataSourceImpl()
        let path = try ds.writeTemplate(format: .toml, force: false)
        try "old content".write(toFile: path, atomically: true, encoding: .utf8)

        let newPath = try ds.writeTemplate(format: .toml, force: true)
        #expect(newPath == path)

        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content == ds.template(format: .toml))
    }

    @Test("existingConfigPath returns path when config file exists")
    func existingPathWhenExists() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer {
            unsetenv("XDG_CONFIG_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }

        let ds = ConfigDataSourceImpl()
        _ = try ds.writeTemplate(format: .toml, force: false)

        #expect(ds.existingConfigPath() == "\(tmp)/lyra/config.toml")
    }

    @Test("existingConfigPath returns nil when no config file exists")
    func existingPathWhenMissing() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer {
            unsetenv("XDG_CONFIG_HOME")
        }

        let ds = ConfigDataSourceImpl()
        #expect(ds.existingConfigPath() == nil)
    }

    @Test("creates intermediate directories")
    func createsDirectories() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        setenv("XDG_CONFIG_HOME", tmp, 1)
        defer {
            unsetenv("XDG_CONFIG_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }

        #expect(!FileManager.default.fileExists(atPath: "\(tmp)/lyra"))

        let ds = ConfigDataSourceImpl()
        _ = try ds.writeTemplate(format: .toml, force: false)

        #expect(FileManager.default.fileExists(atPath: "\(tmp)/lyra"))
    }
}