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
}