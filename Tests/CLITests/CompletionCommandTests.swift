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
    func bashCompletion() {
        withKnownIssue("bash completion output is intermittently flaky", isIntermittent: true) {
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
    packageRoot().appendingPathComponent("Sources/VersionHandler/Resources/\(filename)").path
}

private func packageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
