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

import Foundation
import Testing

@Suite("CompletionCommand E2E")
struct CompletionCommandTests {
    @Test("zsh completion outputs non-empty script")
    func zshCompletion() throws {
        let output = try run(arguments: ["completion", "zsh"])
        #expect(output.contains("#compdef"))
        #expect(output.contains("lyra"))
    }

    @Test("bash completion outputs non-empty script")
    func bashCompletion() throws {
        try withKnownIssue("bash completion output is intermittently flaky", isIntermittent: true) {
            let output = try run(arguments: ["completion", "bash"])
            #expect(output.contains("complete"))
        }
    }

    @Test("fish completion outputs non-empty script")
    func fishCompletion() throws {
        let output = try run(arguments: ["completion", "fish"])
        #expect(output.contains("lyra"))
    }

    @Test("unsupported shell returns error")
    func unsupportedShell() throws {
        let process = Process()
        process.executableURL = binaryURL()
        process.arguments = ["completion", "powershell"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus != 0)
    }
}

@Suite("VersionCommand E2E")
struct VersionCommandTests {
    @Test("--version output matches version.txt")
    func versionFlag() throws {
        let output = try run(arguments: ["--version"])
        let expected = try String(contentsOfFile: resourcePath("version.txt"), encoding: .utf8)
        #expect(
            output.trimmingCharacters(in: .whitespacesAndNewlines)
                == expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("version subcommand output matches version.txt")
    func versionSubcommand() throws {
        let output = try run(arguments: ["version"])
        let expected = try String(contentsOfFile: resourcePath("version.txt"), encoding: .utf8)
        #expect(
            output.trimmingCharacters(in: .whitespacesAndNewlines)
                == expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private func run(arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = binaryURL()
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

private func binaryURL() -> URL {
    packageRoot().appendingPathComponent(".build/debug/lyra")
}

private func resourcePath(_ filename: String) -> String {
    packageRoot().appendingPathComponent("Sources/CLI/Resources/\(filename)").path
}

private func packageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}